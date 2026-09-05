# frozen_string_literal: true

RSpec.describe "owner declaration transaction lifetimes" do
  let(:styles) { ViewComponent::Styles }
  let!(:registry) { with_fresh_registry }

  [false, true].each do |fail_outer|
    [false, true].each do |explicit|
      it "retains theme CSS with its cached owner (explicit=#{explicit}, rollback=#{fail_outer})" do
        vars = styles.define_vars(name: "owner-theme", accent: "red")
        owner = Class.new { include ViewComponent::Styles }
        owner.style_vars(name: "owner-theme", accent: "red") unless explicit
        calls = 0
        block = proc { calls += 1; { accent: "blue" } }
        explicit ? owner.theme(vars, &block) : owner.theme(&block)
        begin
          registry.transaction do
            owner.theme
            styles.create(outer: { padding: 7 })
            raise "outer failure" if fail_outer
          end
        rescue RuntimeError => error
          raise unless error.message == "outer failure"
        end
        2.times do
          expect(registry.to_css).to include(".#{owner.theme.class_names}{#{vars.var_name(:accent)}:blue}")
        end
        expect(calls).to eq(1)
        expect(registry.rules.any? { |rule| rule.property == "padding" }).to eq(!fail_outer)
      end
    end

    [false, true].each do |deferred|
      it "retains variable CSS with its owner sheet (deferred=#{deferred}, rollback=#{fail_outer})" do
        owner = Class.new { include ViewComponent::Styles }
        calls = 0
        begin
          registry.transaction do
            if deferred
              owner.style_vars(name: "owner-vars") { calls += 1; { gap: 2 } }
            else
              owner.style_vars(name: "owner-vars", gap: 2)
            end
            owner.styles
            styles.define_vars(name: "outer-vars", outside: 3)
            raise "outer failure" if fail_outer
          end
        rescue RuntimeError => error
          raise unless error.message == "outer failure"
        end
        2.times do
          variable = owner.styles.vars_for(:gap).var_name(:gap)
          expect(owner.styles.gap).to eq("var(#{variable})")
          expect(registry.to_css).to include(":root{#{variable}:2}")
        end
        expect(calls).to eq(deferred ? 1 : 0)
        expect(registry.rules.any? { |rule| rule.value == "3" }).to eq(!fail_outer)
      end
    end
  end

  [false, true].each do |deferred|
    it "keeps previous vars through a failed replacement and retries (deferred=#{deferred})" do
      owner = Class.new { include ViewComponent::Styles }
      owner.style_vars(name: "retry-owner", gap: 2)
      previous = owner.styles
      baseline = registry.to_css
      values = { gap: 3, extra: { bogus: 4 } }
      declare = proc do
        if deferred
          owner.style_vars(name: "retry-owner") { values }
          owner.styles
        else
          owner.style_vars(name: "retry-owner", **values)
        end
      end
      expect { registry.transaction { declare.call } }.to raise_error(ArgumentError)
      expect(registry.to_css).to eq(baseline)
      expect(previous.var_names).to eq([:gap])
      values = { gap: 3, extra: 4 }
      registry.transaction { deferred ? owner.styles : declare.call }
      variable = owner.styles.vars_for(:gap).var_name(:gap)
      expect(registry.rules.select { |rule| rule.property == variable }.map(&:value)).to eq(["3"])
      expect(owner.styles.var_names).to contain_exactly(:gap, :extra)
    end
  end

  [false, true].each do |explicit|
    it "publishes no partial theme and retries inside an outer transaction (explicit=#{explicit})" do
      vars = styles.define_vars(name: "retry-theme", accent: "red", gap: 2)
      owner = Class.new { include ViewComponent::Styles }
      owner.style_vars(name: "retry-theme", accent: "red", gap: 2) unless explicit
      values = { accent: "blue", gap: { bogus: 4 } }
      explicit ? owner.theme(vars) { values } : owner.theme { values }
      baseline = registry.to_css
      expect { registry.transaction { owner.theme } }.to raise_error(ArgumentError)
      expect(registry.to_css).to eq(baseline)
      values = { accent: "blue", gap: 4 }
      registry.transaction { owner.theme }
      expect(registry.rules.count { |rule| rule.selector == ".#{owner.theme.class_names}" }).to eq(2)
    end
  end
end
