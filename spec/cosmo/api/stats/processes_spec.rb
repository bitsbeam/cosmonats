# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats::Processes do
  subject(:processes) { described_class.new }

  before { processes.instance_variable_get(:@kv).clean rescue nil }
  after { processes.instance_variable_get(:@kv).clean rescue nil }

  describe ".instance" do
    it "returns a singleton" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#register" do
    it "lists the registered process" do
      processes.register("host-1", { identity: "host-1", pid: 1 })
      wait_until(timeout: 5) { processes.size == 1 }
      expect(processes.list).to eq([{ identity: "host-1", pid: 1 }])
    end

    it "overwrites the entry of the same process on every beat" do
      processes.register("host-1", { identity: "host-1", busy: 0 })
      processes.register("host-1", { identity: "host-1", busy: 3 })
      wait_until(timeout: 5) { processes.list.first&.dig(:busy) == 3 }
      expect(processes.size).to eq(1)
    end

    it "accepts identities with characters a KV key cannot hold" do
      processes.register("web 1.local:42", { identity: "web 1.local:42" })
      wait_until(timeout: 5) { processes.size == 1 }
      expect(processes.list.first[:identity]).to eq("web 1.local:42")
    end

    it "recreates the bucket when it was deleted under a running process" do
      processes.register("host-1", { identity: "host-1" })
      client.delete_stream("KV_#{described_class::BUCKET}")

      processes.register("host-1", { identity: "host-1" })
      wait_until(timeout: 5) { processes.size == 1 }
    end
  end

  describe "#unregister" do
    it "removes the process" do
      processes.register("host-1", { identity: "host-1" })
      processes.register("host-2", { identity: "host-2" })
      wait_until(timeout: 5) { processes.size == 2 }

      processes.unregister("host-1")
      wait_until(timeout: 5) { processes.size == 1 }
      expect(processes.list.map { _1[:identity] }).to eq(["host-2"])
    end
  end

  describe "#list" do
    it "pages through processes" do
      3.times { processes.register("host-#{_1}", { identity: "host-#{_1}" }) }
      wait_until(timeout: 5) { processes.size == 3 }

      first = processes.list(page: 1, limit: 2).map { _1[:identity] }
      second = processes.list(page: 2, limit: 2).map { _1[:identity] }
      expect(first.size).to eq(2)
      expect((first + second).sort).to eq(%w[host-0 host-1 host-2])
    end

    it "keeps every process on its page while heartbeats rewrite entries" do
      [["web-b", 2], ["web-a", 9], ["web-a", 10], ["web-c", 1]].each do |host, pid|
        processes.register("#{host}-#{pid}", { hostname: host, pid: pid })
      end
      wait_until(timeout: 5) { processes.size == 4 }
      processes.register("web-a-9", { hostname: "web-a", pid: 9 })

      pages = (1..2).map { |page| processes.list(page:, limit: 2).map { "#{_1[:hostname]}:#{_1[:pid]}" } }
      expect(pages).to eq([%w[web-a:9 web-a:10], %w[web-b:2 web-c:1]])
    end
  end
end
