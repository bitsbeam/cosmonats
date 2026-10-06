# frozen_string_literal: true

require "cosmo/web"

RSpec.describe Cosmo::Web, "processes table" do
  let(:processes) { Cosmo::API::Stats::Processes.instance }

  before { processes.instance_variable_get(:@kv).clean rescue nil }
  after { processes.instance_variable_get(:@kv).clean rescue nil }

  def get(path)
    Rack::MockRequest.new(described_class).get(path)
  end

  it "groups processes by what they subscribe to" do
    processes.register("a-1", { hostname: "a", pid: 1, subscriptions: { streams: ["Orders"] } })
    processes.register("b-2", { hostname: "b", pid: 2, subscriptions: { jobs: ["default"], streams: [] } })
    processes.register("c-3", { hostname: "c", pid: 3, subscriptions: { jobs: ["default"], streams: ["Orders"] } })
    processes.register("d-4", { hostname: "d", pid: 4, subscriptions: { streams: ["Events"] } })
    wait_until(timeout: 5) { processes.size == 4 }

    body = get("/jobs/_processes?poll=0").body
    groups = body.scan(/<tr class="group-row">\s*<td colspan="10">([^<]+) <span class="text-muted">\((\d+)\)/)
    rows = body.scan(%r{<div class="job-class">([^<]+)</div>}).flatten

    expect(groups).to eq([["Jobs", "1"], ["Streams", "2"], ["Jobs &amp; Streams", "1"]])
    expect(rows).to eq(%w[b:2 a:1 d:4 c:3])
  end
end
