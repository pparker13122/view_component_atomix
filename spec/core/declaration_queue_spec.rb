# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::DeclarationQueue do
  it "retries failed and remaining work before newly enqueued work without repeating successes" do
    queue = described_class.new
    %i[first failed last].each { |item| queue << item }
    completed = []
    expect do
      queue.drain do |item|
        if item == :failed
          queue << :new
          raise "retry"
        end
        completed << item
      end
    end.to raise_error("retry")

    queue.drain { |item| completed << item }
    queue.drain { raise "already consumed" }
    expect(completed).to eq(%i[first failed last new])
  end

  it "allows reentrant drains without repeating in-progress declarations" do
    queue = described_class.new
    queue << :outer
    completed = []
    queue.drain do |item|
      queue << :inner
      queue.drain { |nested| completed << nested }
      completed << item
    end
    expect(completed).to eq(%i[inner outer])
  end

  it "shares a direct drain budget and restores retry order when it is exceeded" do
    stub_const("ViewComponent::Atomix::DeclarationQueue::MAX_DRAIN_PASSES", 2)
    queue = described_class.new
    %i[done outer last].each { |item| queue << item }
    completed = []
    expect do
      queue.drain do |item|
        if item == :outer
          queue << :inner
          queue.drain do |_nested|
            queue << :new
            queue.drain { raise "must not run" }
          end
        end
        completed << item
      end
    end.to raise_error(ArgumentError, /keep adding work/)

    expect(completed).to eq([:done])
    queue.drain { |item| completed << item }
    expect(completed).to eq(%i[done outer last inner new])
  end
end
