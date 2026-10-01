# frozen_string_literal: true

RSpec.describe Cosmo::HTTPServer::Ping do
  let(:inner) { ->(_env) { [418, {}, ["inner"]] } }
  let(:middleware) { described_class.new(inner) }

  def request(path, method: "GET")
    middleware.call(Rack::MockRequest.env_for(path, method: method))
  end

  it "passes other paths down the stack" do
    expect(request("/other")).to eq([418, {}, ["inner"]])
  end

  it "returns 200 without running any checks" do
    expect(Cosmo::Engine).not_to receive(:instance)
    expect(Cosmo::Client).not_to receive(:instance)
    status, headers, body = request("/ping")
    expect(status).to eq(200)
    expect(headers["content-type"]).to eq("text/plain")
    expect(body).to eq(["pong"])
  end

  it "rejects non-GET methods" do
    status, headers, = request("/ping", method: "POST")
    expect(status).to eq(405)
    expect(headers["allow"]).to eq("GET, HEAD")
  end
end
