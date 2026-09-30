# frozen_string_literal: true

require "net/http"

RSpec.describe Cosmo::HTTPServer do
  subject(:server) { described_class.new(host: "127.0.0.1", port: 0).start }

  after { server.stop }

  before { allow(Cosmo::Engine.instance).to receive(:running?).and_return(true) }

  def get(path)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{server.port}#{path}"))
  end

  it "serves /health" do
    response = get("/health")
    expect(response.code).to eq("200")
    expect(JSON.parse(response.body)).to eq("status" => "ok", "checks" => { "engine" => true, "nats" => true })
  end

  it "returns 404 for unknown paths" do
    expect(get("/nope").code).to eq("404")
  end
end
