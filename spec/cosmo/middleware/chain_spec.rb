# frozen_string_literal: true

RSpec.describe Cosmo::Middleware::Chain do
  subject(:chain) { described_class.new }

  let(:tagger) do
    Class.new do
      def initialize(tag, log:)
        @tag = tag
        @log = log
      end

      def call(*args)
        @log << [:before, @tag, args]
        result = yield
        @log << [:after, @tag]
        result
      end
    end
  end
  let(:first) { Class.new(tagger) }
  let(:second) { Class.new(tagger) }
  let(:third) { Class.new(tagger) }
  let(:log) { [] }

  def classes
    chain.map(&:klass)
  end

  describe "#invoke" do
    it "runs the block when the chain is empty" do
      expect(chain.invoke(:job) { :done }).to eq(:done)
    end

    it "wraps the block in every middleware, outermost first, passing the arguments to each" do
      chain.add(first, :a, log:).add(second, :b, log:)

      result = chain.invoke(:job, :data, :message) do
        log << :perform
        :done
      end

      expect(result).to eq(:done)
      expect(log).to eq([[:before, :a, %i[job data message]], [:before, :b, %i[job data message]],
                         :perform, %i[after b], %i[after a]])
    end

    it "builds fresh middleware instances on every invocation" do
      instances = []
      recorder = Class.new do
        define_method(:call) do |*, &block|
          instances << self
          block.call
        end
      end
      chain.add(recorder)

      2.times { chain.invoke { nil } }

      expect(instances.uniq.size).to eq(2)
    end

    it "skips the rest of the chain and the block when a middleware does not yield" do
      halt = Class.new { def call(*) = :halted }
      chain.add(halt).add(first, :a, log:)

      expect(chain.invoke { log << :perform }).to eq(:halted)
      expect(log).to be_empty
    end
  end

  describe "ordering" do
    it "moves an already registered class instead of adding it twice" do
      chain.add(first, :a, log:).add(second, :b, log:).add(first, :a, log:)

      expect(classes).to eq([second, first])
    end

    it "prepends, inserts before and after a class, and removes it" do
      chain.add(second, :b, log:)
      chain.prepend(first, :a, log:)
      chain.insert_after(first, third, :c, log:)
      expect(classes).to eq([first, third, second])

      chain.insert_before(first, second)
      expect(classes).to eq([second, first, third])

      chain.remove(first)
      expect(classes).to eq([second, third])
      expect(chain.exists?(first)).to be(false)
      expect(chain.exists?(third)).to be(true)
    end

    it "inserts at the edges when the anchor class is missing" do
      missing = Class.new
      chain.add(first, :a, log:)
      chain.insert_before(missing, second, :b, log:)
      chain.insert_after(missing, third, :c, log:)

      expect(classes).to eq([second, first, third])
    end

    it "clears every entry" do
      chain.add(first, :a, log:)

      expect(chain.clear).to be_empty
    end
  end
end
