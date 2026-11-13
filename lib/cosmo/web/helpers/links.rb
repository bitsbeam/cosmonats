# frozen_string_literal: true

module Cosmo
  class Web
    module Helpers
      # Links out of the UI, configured through +config.web+.
      module Links
        # A job ID cell: a link when +config.web.jid_link+ gives one for this job, plain text otherwise.
        #
        # @param data [Hash] the job's payload, +:jid+, +:class+, +:args+, ...
        # @param stream [String, Symbol, nil] the job's stream, when known
        # @return [String] the HTML
        def jid_cell(data, stream: nil)
          jid = data[:jid]
          url = jid_url(stream ? data.merge(stream: stream.to_s) : data)
          attrs = %(class="mono ellip#{" mute" unless url}" style="font-size:11.5px" title="#{h(jid)}")
          return %(<span #{attrs}>#{h(jid)}</span>) unless url

          %(<a #{attrs} href="#{h(url)}" target="_blank" rel="noopener noreferrer">#{h(jid)}</a>)
        end

        # A batch ID: a link when +config.web.bid_link+ gives one for this batch, plain text otherwise.
        #
        # @param batch [Cosmo::API::Batch]
        # @param attrs [String] extra HTML attributes for the element
        # @return [String] the HTML
        def bid_cell(batch, attrs: "")
          bid = batch.bid
          url = bid_url(bid:, parent_id: batch.parent_id, description: batch.description)
          attrs = %(class="mono strong ellip#{" mute" unless url}" #{attrs})
          return %(<span #{attrs}>#{h(bid)}</span>) unless url

          %(<a #{attrs} href="#{h(url)}" target="_blank" rel="noopener noreferrer">#{h(bid)}</a>)
        end

        # @param data [Hash] the job's payload, with +:stream+ when known
        # @return [String, nil] the http(s) URL +config.web.jid_link+ gives for the job, nil without one or on error
        def jid_url(data)
          resolve_link(Config.web.jid_link, data, %w[jid class stream], data[:jid])
        end

        # @param data [Hash] the batch's +:bid+, +:parent_id+ and +:description+
        # @return [String, nil] the http(s) URL +config.web.bid_link+ gives for the batch, nil without one or on error
        def bid_url(data)
          resolve_link(Config.web.bid_link, data, %w[bid parent_id], data[:bid])
        end

        private

        def resolve_link(link, data, keys, id)
          return unless link

          url =
            if link.is_a?(String)
              # gsub rather than format, so a template's own %-escapes (e.g. Grafana's %22) are left alone
              link.gsub(/%\{(#{keys.join("|")})\}/) { u(data[::Regexp.last_match(1).to_sym]) }
            else
              link.call(data)
            end
          url = url&.to_s
          url if url&.match?(%r{\Ahttps?://}i)
        rescue StandardError => e
          Logger.debug("web link failed for #{id}: #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
