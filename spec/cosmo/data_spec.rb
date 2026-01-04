# frozen_string_literal: true

RSpec.describe Cosmo::Job::Data do
  let(:data) { described_class.new("MyJob", "args", stream: "default") }

  it "#jid" do
    expect(data.jid).not_to be(nil)
    expect(data.jid.size).to eq(24)
  end

  it "#stream" do
    expect(data.stream).to eq("default")
  end

  it "#subject" do
    expect(data.subject).to eq(%w[jobs default my_job])
  end

  it "#as_json" do
    allow(data).to receive(:jid).and_return("jid")

    expect(data.as_json).to eq({ args: "args", class: "MyJob", dead: true, jid: "jid", retry: 3 })
  end

  it "#to_json" do
    allow(data).to receive(:jid).and_return("jid")

    expect(data.to_json).to eq(%({"jid":"jid","class":"MyJob","args":"args","retry":3,"dead":true}))
  end

  it "#to_args" do
    allow(data).to receive(:jid).and_return("jid")

    expect(data.to_args).to eq(["jobs.default.my_job",
                                %({"jid":"jid","class":"MyJob","args":"args","retry":3,"dead":true}),
                                { header: { "Nats-Msg-Id" => "jid" }, stream: "default" }])
  end
end
