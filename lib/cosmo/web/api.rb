# frozen_string_literal: true

module Cosmo
  class Web
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    class Api
      def stats
        processed = failed = scheduled = dead = 0
        stream_names = client.list_streams
        details = []

        stream_names.each do |name|
          info  = client.stream_info(name)
          state = stream_state(info)
          details << { name: name, messages: state.messages, bytes: state.bytes, consumers: state.consumer_count }

          case name
          when "scheduled"
            scheduled += state.messages
          when "dead"
            dead += state.messages
          else
            processed += state.messages
          end
        end

        { processed: processed, failed: failed,
          scheduled: scheduled, dead: dead,
          stream_names: stream_names, details: details }
      end

      def scheduled(limit)
        jobs = []
        limit = (limit || 50).to_i

        info  = client.stream_info("scheduled")
        state = stream_state(info)
        from  = [state.last_seq - limit + 1, 1].max
        from.upto(state.last_seq) do |seq|
          msg  = client.get_message("scheduled", seq)
          next unless msg

          data = Utils::Json.parse(msg.data)
          jobs << { jid: data["jid"], klass: data["class"], args: data["args"], at: data["at"], seq: seq }
        end

        jobs.sort_by! { |j| j[:at].to_f }
        { jobs: jobs, total: state.messages }
      end

      def dead(limit)
        jobs = []
        limit  = (limit || 50).to_i

        info  = client.stream_info("dead")
        state = stream_state(info)
        from  = [state.last_seq - limit + 1, 1].max
        from.upto(state.last_seq) do |seq|
          msg  = client.get_message(stream_name, seq)
          next unless msg

          data = Utils::Json.parse(msg.data)
          jobs << { jid: data["jid"], klass: data["class"], args: data["args"], error: data["error"], failed_at: data["failed_at"], seq: seq }
        end

        jobs.sort_by! { |j| j[:failed_at].to_f }.reverse!
        { jobs: jobs, total: state.messages }
      end

      def retry(stream_name, seq)
        msg = client.get_message(stream_name, seq)
        data = Utils::Json.parse(msg.data)
        client.publish("jobs.#{data["stream"] || "default"}.#{data["class"]}", msg.data)
      end

      def streams
        streams = client.list_streams.filter_map do |name|
          info  = client.stream_info(name)
          state = stream_state(info)
          { name: name, messages: state.messages, bytes: state.bytes,
            first_seq: state.first_seq, last_seq: state.last_seq,
            consumer_count: state.consumer_count, subjects: info.config.subjects }
        end

        { streams: streams }
      end

      def info(name)
        info  = client.stream_info(name)
        state = stream_state(info)
        { name: name, state: state, config: info.config }
      end

      private

      def client
        @client ||= Client.instance
      end

      def stream_state(info)
        info.config.respond_to?(:state) ? info.config.state : info.state
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
