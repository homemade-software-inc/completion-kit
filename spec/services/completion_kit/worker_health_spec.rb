require "rails_helper"

RSpec.describe CompletionKit::WorkerHealth do
  describe ".healthy?" do
    context "when SolidQueue::Process is not defined" do
      around do |example|
        if defined?(::SolidQueue::Process)
          original = ::SolidQueue.const_get(:Process)
          ::SolidQueue.send(:remove_const, :Process)
          example.run
          ::SolidQueue.const_set(:Process, original)
        else
          example.run
        end
      end

      it "returns true (other adapters in use; treat as healthy)" do
        expect(described_class.healthy?).to eq(true)
      end
    end

    context "when SolidQueue::Process is defined" do
      let(:fake_process_class) do
        Class.new do
          class << self
            attr_accessor :exists_result
            def where(*)
              klass = self
              relation = Object.new
              relation.define_singleton_method(:where) { |*| self }
              relation.define_singleton_method(:exists?) { klass.exists_result }
              relation
            end
          end
        end
      end

      before do
        stub_const("SolidQueue", Module.new) unless defined?(::SolidQueue)
        stub_const("SolidQueue::Process", fake_process_class)
      end

      it "returns true when at least one process has heartbeat'd within threshold" do
        fake_process_class.exists_result = true
        expect(described_class.healthy?).to eq(true)
      end

      it "returns false when no process has heartbeat'd within threshold" do
        fake_process_class.exists_result = false
        expect(described_class.healthy?).to eq(false)
      end
    end
  end
end
