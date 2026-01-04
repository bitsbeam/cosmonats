# frozen_string_literal: true

module Nested
  class Base # rubocop:disable Lint/EmptyClass
  end
end

RSpec.describe Cosmo::Utils::String do
  it ".underscore" do
    expect(described_class.underscore("Class")).to eq("class")
    expect(described_class.underscore("MyClass")).to eq("my_class")
    expect(described_class.underscore("MyHTTPServer")).to eq("my_http_server")
    expect(described_class.underscore("Admin::UserProfile")).to eq("admin-user_profile")
    expect(described_class.underscore("Admin::UserProfileSuPER")).to eq("admin-user_profile_su_per")
  end

  it ".safe_constantize" do
    expect(described_class.safe_constantize("Class")).to eq(Class)
    expect(described_class.safe_constantize("Nested::Base")).to eq(Nested::Base)
    expect(described_class.safe_constantize("Nested::Basic")).to be_nil
    expect(described_class.safe_constantize("foo")).to be_nil
  end
end
