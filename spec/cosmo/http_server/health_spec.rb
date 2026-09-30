# frozen_string_literal: true

RSpec.describe Cosmo::HTTPServer::Health do
  let(:inner) { ->(_env) { [418, {}, ["inner"]] } }
  let(:checks) { { engine: true, nats: true } }
  let(:middleware) { described_class.new(inner, check: -> { checks }) }

  def request(path, method: "GET")
    middleware.call(Rack::MockRequest.env_for(path, method: method))
  end

  it "passes other paths down the stack" do
    expect(request("/other")).to eq([418, {}, ["inner"]])
  end

  it "returns 200 when all checks pass" do
    status, headers, body = request("/health")
    expect(status).to eq(200)
    expect(headers["content-type"]).to eq("application/json")
    expect(JSON.parse(body.join)).to eq("status" => "ok", "checks" => { "engine" => true, "nats" => true })
  end

  context "when a check fails" do
    let(:checks) { { engine: true, nats: false } }

    it "returns 503" do
      status, _, body = request("/health")
      expect(status).to eq(503)
      expect(JSON.parse(body.join)["status"]).to eq("unavailable")
    end
  end

  it "rejects non-GET methods" do
    status, headers, = request("/health", method: "POST")
    expect(status).to eq(405)
    expect(headers["allow"]).to eq("GET, HEAD")
  end

  it "uses engine and NATS state by default" do
    allow(Cosmo::Engine.instance).to receive(:running?).and_return(false)
    status, _, body = described_class.new(inner).call(Rack::MockRequest.env_for("/health"))
    expect(status).to eq(503)
    expect(JSON.parse(body.join)["checks"]).to eq("engine" => false, "nats" => true)
  end
end
