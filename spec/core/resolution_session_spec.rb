# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::ResolutionSession do
  it "marks every frame in progress as stale without letting one frame clear another's mark" do
    described_class.with do |session|
      session.frame do |outer|
        session.frame do |inner|
          described_class.stale!
          expect([outer.stale, inner.stale]).to eq([true, true])
          inner.stale = false
          expect(outer.stale).to be(true)
        end
      end
    end
  end

  it "starts a nested frame unmarked while keeping an earlier mark on the outer frame" do
    described_class.with do |session|
      session.frame do |outer|
        described_class.stale!
        session.frame { |inner| expect(inner.stale).to be(false) }
        expect(outer.stale).to be(true)
      end
    end
  end

  it "ignores stale marks when nothing is in progress" do
    expect(described_class.stale!).to be_nil
  end
end
