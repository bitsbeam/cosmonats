# frozen_string_literal: true

class MyJob
  include Cosmo::Job
end

class Child < MyJob
end

class CustomChild < MyJob
  options stream: :custom
end

class CustomCustomChild < CustomChild
  include Cosmo::Job
end

RSpec.describe Cosmo::Job do
  it "#options" do
    expect(MyJob.default_options).to eq({ dead: true, retry: 3, stream: :default })
    expect(Child.default_options).to eq({ dead: true, retry: 3, stream: :default })
    expect(CustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom })
    expect(CustomCustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom })

    CustomChild.default_options[:stream] = :none
    expect(CustomChild.default_options).to eq({ dead: true, retry: 3, stream: :none })
    expect(CustomCustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom })
  end
end
