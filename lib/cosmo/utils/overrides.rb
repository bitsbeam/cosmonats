# frozen_string_literal: true

Cosmo::Utils::Warnings.silence do
  members = NATS::JetStream::API::StreamConfig.members + %i[allow_msg_counter allow_msg_schedules]
  NATS::JetStream::API::StreamConfig = Struct.new(*members, keyword_init: true) do
    def initialize(opts = {})
      rem = opts.keys - members
      opts.delete_if { |k| rem.include?(k) }
      super
    end
  end

  members = NATS::JetStream::PubAck.members + [:val]
  NATS::JetStream::PubAck = Struct.new(*members, keyword_init: true)
end

# Upstream bug in nats-pure 2.5.0 (https://github.com/nats-io/nats.rb):
# NATS::JetStream::PullSubscription#fetch only assigns its `start_time` local in the
# `batch > 1` branch, but the final "did we time out" check outside the case statement
# reads it unconditionally. For `batch == 1` (what Cosmo::Processor always uses),
# `start_time` is nil there -- normally masked because the `batch == 1` branch has its
# own timeout check (using a properly-set `t`) that raises first.
#
# It only surfaces once two threads call #fetch concurrently on the *same* subscription:
# @pending_queue/wait_for_msgs_cond are shared per-subscription state, and #dispatch's
# `wait_for_msgs_cond.signal` wakes exactly one arbitrary waiter -- not necessarily the
# one whose own request produced that wakeup. A thread woken by someone else's signal
# finds nothing left in the (already-drained) queue, so it skips its own inner timeout
# check and falls into the buggy tail check, raising `TypeError: nil can't be coerced
# into Float` instead of the intended timeout/empty result. Reproduced deterministically
# with N threads fetching in a loop against the same PullSubscription.
#
# Second, separate upstream bug in the same method: the post-wait timeout check below
# (`raise ... if MonotonicTime.since(t) > timeout`) fires unconditionally, unlike every
# other timeout check in this method (all guarded with `msgs.empty? &&`). If the unsynchronized
# pop just above it succeeded in grabbing a real, already-delivered message -- which can happen
# even after `timeout` has technically elapsed, since #dispatch's signal and this thread actually
# resuming are two different moments -- that message is already gone from @pending_queue with
# nowhere else to go, yet gets discarded here and a plain NATS::Timeout raised instead. Callers
# (including Cosmo::Processor#fetch) treat NATS::Timeout as "no messages", so the message is lost
# silently: never processed, never acked, and not redelivered until the consumer's ack_wait expires.
# Reproduces reliably with several threads fetching (batch: 1) concurrently against the same
# subscription, e.g. Cosmo::Job::Processor's thread pool.
#
# Vendored copy of nats-pure's PullSubscription#fetch, kept as close to
# upstream as possible (two one-line fixes, see comments above), so it's easy to diff against the
# next nats-pure release and drop once fixed there.

# rubocop:disable all
module NATS
  class JetStream
    module PullSubscription
      def fetch(batch = 1, params = {})
        raise ::NATS::JetStream::Error.new("nats: invalid batch size") if batch < 1

        t = MonotonicTime.now
        start_time = t # fixes the upstream bug -- see comment above
        timeout = params[:timeout] ||= 5
        expires = (timeout * 1_000_000_000) - 100_000
        next_req = { batch: batch }

        msgs = []
        case
        when batch == 1
          synchronize do
            unless @pending_queue.empty?
              msg = @pending_queue.pop
              @pending_size -= msg.data.size
              if JS.is_status_msg(msg)
                case msg.header["Status"]
                when JS::Status::NoMsgs then nil
                when JS::Status::RequestTimeout then nil # Skip
                else raise JS.from_msg(msg)
                end
              else
                msgs << msg
              end
            end
          end

          next_req[:expires] = expires
          if msgs.empty?
            @nc.publish(@jsi.nms, JS.next_req_to_json(next_req), @subject)
            synchronize { wait_for_msgs_cond.wait(timeout) }

            unless @pending_queue.empty?
              msg = @pending_queue.pop
              @pending_size -= msg.data.size
              msgs << msg
            end

            raise ::NATS::Timeout.new("nats: fetch timeout") if msgs.empty? && (MonotonicTime.since(t) > timeout)

            if JS.is_status_msg(msgs.first)
              msg = msgs.first
              case msg.header[JS::Header::Status]
              when JS::Status::RequestTimeout then raise NATS::Timeout.new("nats: fetch request timeout")
              else raise JS.from_msg(msgs.first)
              end
            end
          end
        when batch > 1
          synchronize do
            if batch <= @pending_queue.size
              batch.times do
                msg = @pending_queue.pop
                @pending_size -= msg.data.size
                if JS.is_status_msg(msg)
                  case msg.header[JS::Header::Status]
                  when JS::Status::NoMsgs, JS::Status::RequestTimeout then next
                  else raise JS.from_msg(msg)
                  end
                else
                  msgs << msg
                end
              end
              return msgs
            end
          end

          next_req[:no_wait] = true
          @nc.publish(@jsi.nms, JS.next_req_to_json(next_req), @subject)

          start_time = MonotonicTime.now
          msg = nil

          synchronize do
            wait_for_msgs_cond.wait(timeout)
            unless @pending_queue.empty?
              msg = @pending_queue.pop
              @pending_size -= msg.data.size
            end
          end

          if !msg.nil? && JS.is_status_msg(msg)
            case msg.header[JS::Header::Status]
            when JS::Status::NoMsgs
              next_req[:expires] = expires
              next_req.delete(:no_wait)
              @nc.publish(@jsi.nms, JS.next_req_to_json(next_req), @subject)
            when JS::Status::RequestTimeout
              raise NATS::Timeout.new("nats: fetch request timeout")
            else
              raise JS.from_msg(msg)
            end
          else
            msgs << msg unless msg.nil?
          end

          duration = MonotonicTime.since(start_time)
          raise NATS::Timeout.new("nats: fetch timeout") if msgs.empty? && (duration > timeout)

          needed = batch - msgs.count
          while (needed > 0) && (MonotonicTime.since(start_time) < timeout)
            duration = MonotonicTime.since(start_time)

            synchronize do
              if @pending_queue.empty?
                deadline = timeout - duration
                wait_for_msgs_cond.wait(deadline) if deadline > 0

                duration = MonotonicTime.since(start_time)
                if msgs.empty? && @pending_queue.empty? && (duration > timeout)
                  raise NATS::Timeout.new("nats: fetch timeout")
                end
              end

              unless @pending_queue.empty?
                msg = @pending_queue.pop
                @pending_size -= msg.data.size

                if JS.is_status_msg(msg)
                  case msg.header[JS::Header::Status]
                  when JS::Status::NoMsgs, JS::Status::RequestTimeout
                    duration = MonotonicTime.since(start_time)
                    if duration > timeout
                      raise NATS::Timeout.new("nats: fetch timeout") if msgs.empty?

                      return msgs
                    end
                  else
                    raise JS.from_msg(msg)
                  end
                else
                  msgs << msg
                  needed -= 1
                end
              end
            end
          end
        end

        raise ::NATS::Timeout.new("nats: fetch timeout") if msgs.empty? && (MonotonicTime.since(start_time) > timeout)

        msgs
      end
    end
  end
end
# rubocop:enable all
