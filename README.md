# ViewComponent::Styles

StyleX-like atomic CSS for [ViewComponent](https://viewcomponent.org) and plain Rails views. You declare styles in Ruby, next to the component that uses them. Each property/value pair compiles to one deterministic atomic class, styles merge per property with last-wins semantics, and the CSS is collected in a registry and emitted with no JavaScript build step.

```ruby
class ButtonComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    trait :button, padding: "8px 16px",
                   border_radius: 4,
                   background: { default: "#fff", hover: "#eee" }

    trait :size, default: :md,
                 sm: { font_size: 14 },
                 md: { font_size: 16 },
                 lg: { font_size: 20 }
  end

  def initialize(size: nil)
    @size = size
  end

  erb_template <<~ERB
    <button <%= styles.props(styles.button, styles.size(@size)) %>><%= content %></button>
  ERB
end
```

`render ButtonComponent.new(size: :lg)` produces:

```html
<button class="vc4dud5thf vc968v4d1e vcph2rfytx vc8ii37bsa vcigwbeo1f">
```

and the stylesheet contains one rule per declaration:

```css
.vc4dud5thf{padding:8px 16px}
.vcph2rfytx{background:#fff}
.vc8ii37bsa:hover{background:#eee}
.vc968v4d1e{border-radius:4px}
.vcooz8b8nn{font-size:14px}
.vc34mq84yv{font-size:16px}
.vcigwbeo1f{font-size:20px}
```

A few ideas run through everything below:

- A **trait** is a named group of declarations. `trait :button, ...` declares one and `styles.button` reads it back as a `Style`.
- A **Style** is a set of class names, one per property. Passing several to `styles.props` merges them property by property, so the last style to set a property wins.
- **Conditions** such as `hover` or a breakpoint nest inside a property's value, which is what keeps per-property merging correct.
- Every rule lands in a global **registry**, and the layout tag emits it as CSS.

## Installation

```ruby
gem "view_component_styles"
```

Add the stylesheet tag to your layout:

```erb
<head>
  <%= view_component_styles_tag %>
</head>
```

### Development and production

Outside production the tag inlines a `<style>` block, so there is nothing to build while developing. Whenever the app boots or reloads, the gem loads `app/components` and `app/styles` first so the block contains every style.

In production the tag links `view_component_styles.css`, which `rake view_component:styles:build` writes to `app/assets/builds/`. The build task is inserted as the first prerequisite of `assets:precompile`, so it runs before any `css:build` or `javascript:build` step. Add the output file to `.gitignore`.

Sprockets users need `//= link_tree ../builds` in `app/assets/config/manifest.js`. Propshaft picks the file up automatically.

Like tailwindcss-rails, this gem targets the Rails asset pipeline and does not integrate with esbuild, Vite, or other JavaScript bundlers. Apps using jsbundling-rails or cssbundling-rails still have the pipeline serving `app/assets/builds`, so they work unchanged.

## Declaring styles

`include ViewComponent::Styles` in a component and open a `styles` block. Each `trait` call declares a named style, and `styles` with no block returns the compiled sheet, both at the class level and inside templates.

```ruby
# app/components/card_component.rb
class CardComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    trait :card, display: "flex", gap: 8, padding: 16
    trait :compact, gap: 4, padding: 8
  end

  def initialize(compact: false)
    @compact = compact
  end

  erb_template <<~ERB
    <div <%= styles.props(styles.card, @compact && styles.compact) %>><%= content %></div>
  ERB
end

CardComponent.styles.card       # => Style
CardComponent.styles[:compact]  # => Style
CardComponent.styles.names      # => [:card, :compact]
```

Calling `styles` again merges into the same sheet, and subclasses extend their parent's sheet without changing it. A trait declared later with the same name replaces the earlier one.

The block is evaluated when the sheet is first read, not when the class loads, so a trait can reference a constant that is not loaded yet. Class-level methods, including `styles` itself, work inside the block.

```ruby
class BadgeComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    trait :root, color: Brand::VARS.primary
  end
end
```

### Values

- **Numbers** become `px` except for unitless properties such as `line_height`, `opacity`, `z_index`, `flex` and `font_weight`. Zero stays `0`.
- **Symbols** become kebab-case values, so `display: :inline_block` works.
- **Arrays** emit fallback declarations in order: `position: %w[sticky fixed]`.
- **nil** unsets the property, removing whatever an earlier style set.
- **Keys** are snake_case symbols (`border_radius`), camelCase strings, or raw CSS names. Custom properties like `"--gap"` pass through.

### Conditions

A condition is a pseudo-class, media query, or breakpoint. Conditions live inside a property's value, never at the top level of a trait. This is what makes per-property merging correct: a later style that sets `background` replaces the base value *and* its hover value.

```ruby
styles do
  trait :root,
        color: {
          default: "#111",
          hover: "#000",
          md: { default: "#222", hover: "#333" },
          ":nth-child(2)" => "red",
          "@supports (display: grid)" => "blue"
        },
        before: { content: '""', display: "block" }
end
```

Symbol keys resolve to pseudo-classes (`hover`, `focus`, `focus_visible`, `focus_within`, `active`, `disabled`, `checked`, `first_child`, `last_child`, `placeholder_shown`, ...), a few media shortcuts (`dark`, `light`, `reduced_motion`, `print`), or breakpoints you configure. String keys must start with `:` or `@` and are passed through as written, so any selector or at-rule is available without configuration. Keep raw queries in constants if you want names:

```ruby
module Breakpoints
  TABLET = "@media (max-width: 768px)"
end

styles do
  trait :root, padding: { default: 16, Breakpoints::TABLET => 12 }
end
```

Pseudo-elements (`before`, `after`, `placeholder`, `selection`, `marker`) are the one exception to nesting: they are top-level keys containing their own properties, as `before` is above.

### Breakpoints

Breakpoints are symbols you name yourself, and there are none by default. Configure them app-wide, or declare them inside a `styles` block with `breakpoints`, which scopes them to that component and its subclasses and overrides the app-wide value for the same name:

```ruby
# config/application.rb or an initializer
config.view_component.styles.breakpoints = {
  sm: "(max-width: 640px)",
  md: "(max-width: 768px)"
}

# app/components/hero_component.rb
styles do
  breakpoints wide: "(min-width: 1400px)", md: "(max-width: 900px)"

  trait :root, padding: { default: 16, md: 12, wide: 32 }
end
```

Breakpoints declared in a block apply to that block and every later `styles` block on the class, so put them in the first one.

## Applying styles

`styles.props` takes any number of styles and returns the `class` and `style` attributes for an element. It skips `nil` and `false`, so conditionals read naturally:

```erb
<div <%= styles.props(styles.root, active? && styles.highlighted, @extra) %>>
```

The return value is a Hash of `class` and `style` that also renders as an escaped attribute string, so it works both interpolated into ERB and splatted into a tag helper: `tag.div(**styles.props(styles.root))`. Every sheet has `props`, so `css.props` and `pill_styles.props` later in this guide are the same method.

Merging is per CSS property, and the last argument to set a property wins. Shorthand and longhand properties are distinct keys, and the emitted CSS is sorted so longhands come after shorthands and `:active` after `:hover`. That means `padding_top` always beats `padding` regardless of definition order.

Plain views have no `styles` reader, so they use the `sx` helper instead. It takes the same arguments as `props` and is available in every view and template, along with `sx_attrs`, which returns the Hash form for `tag.div(**sx_attrs(...))`. Outside views, `ViewComponent::Styles.props` and `ViewComponent::Styles.sx` do the same.

## Kinds of traits

A trait is one of four things, told apart by the shape of what follows the name:

```ruby
styles do
  trait :button, padding: 8, border_radius: 4              # plain: a hash of properties
  trait :size, default: :md, sm: { font_size: 14 },         # enumerated: a hash of member hashes
               md: { font_size: 16 }, lg: { font_size: 20 }
  trait :cta, :button, size: :lg, font_weight: 700          # combination: references to earlier traits
  trait :sized, ->(w) { { width: w } }                      # dynamic: a lambda
end
```

### Plain traits

A hash of properties compiles to a `Style`, and `styles.button` reads it. `trait :small, { padding: 6 }` with an explicit hash is the same thing.

### Enumerated traits

A hash whose values are all hashes of properties declares named members. `styles.size(:lg)` returns the member, `styles.size(nil)` and `styles.size` return the default or an empty style, and an unknown member raises `KeyError`. `default:` is optional.

A hash is read as members only when no key is a CSS property, a pseudo-element, a pseudo-class symbol such as `hover`, or a configured breakpoint. Nothing is configured by default, so `sm`, `md` and `lg` are free to use as members until you claim them as breakpoints. A name that is a breakpoint cannot also name a member, and mixing members with properties raises.

### Combination traits

A combination references traits declared earlier: in this block, an earlier `styles` block, a parent class, or a shared module merged into the same sheet. Bare symbols after the name include plain traits, and a keyword whose name is an enumerated trait selects a member. `name: true` also works, and on an enumerated trait it selects the default. Every other keyword is a property. The result is `props` of the references in order followed by the properties, so the properties win. Dynamic traits cannot be referenced.

### Dynamic traits

A lambda value becomes a dynamic style. The class it compiles to reads a CSS variable, and calling it sets that variable inline.

```ruby
styles do
  trait :box, ->(w, h) { { width: w, height: h } }
end

styles.box(120, 40)   # class="vc…" style="--vc…:120px;--vc…:40px"
styles.box(nil)       # empty style
```

The lambda is probed once at definition time to learn which properties it produces, so the keys it returns must not depend on the argument values.

### Naming traits

Because reference keys in a combination are told apart from property keys by name, a trait cannot be named after a CSS property. That rules out some tempting names: `width`, `container`, `content`, `overlay`, `marker`, `fill`, `page`, `top`. Use `sized`, `wrapper`, `body`, `backdrop`, or similar.

A trait whose name collides with a method on `Object` or the sheet (`p`, `select`, `hash`, `props`, `names`) is still declared, but must be read with `styles[:p]` instead of `styles.p`.

## Sharing styles

Styles can live in three places, and they combine freely:

- **In a component** with the `styles` block, as above. Subclasses inherit the sheet.
- **In a shared module** that includes `ViewComponent::Styles`, then included into components.
- **In plain Ruby** as constants built with `ViewComponent::Styles.create`, referenced from anywhere.

### Shared modules

A module can `include ViewComponent::Styles` and declare traits in a `styles` block. Including that module in a component exposes its sheet under an accessor derived from the module name, at the class level and inside templates. The component's own `styles` stays separate.

The accessor is the underscored module name, namespaces included, with a trailing `Styles`, `Style`, `Theme`, `Vars` or `Variables` removed, plus `_styles`. `PillStyles` becomes `pill_styles`, `Admin::ProfileCardStyles` becomes `admin_profile_card_styles`, and `DarkModeStyle` becomes `dark_mode_styles`.

```ruby
# app/styles/pill_styles.rb
module PillStyles
  include ViewComponent::Styles

  styles do
    trait :pill, display: :inline_block, border_radius: 999, padding: "2px 8px"
  end
end

# app/components/pill_component.rb
class PillComponent < ViewComponent::Base
  include PillStyles

  styles do
    trait :tone, color: "#0055ff"
  end

  erb_template <<~ERB
    <span <%= styles.props(pill_styles.pill, styles.tone) %>><%= content %></span>
  ERB
end

PillComponent.styles.names       # => [:tone]
PillComponent.pill_styles.names  # => [:pill]
```

Use a plain module. One that extends `ActiveSupport::Concern` defers the include, so `styles` is not available inside the module body. An anonymous module has no name to derive an accessor from, so its traits merge into the component's `styles` instead.

Style files live in either `app/styles` or `app/components/styles`. Both are autoload roots, so `app/components/styles/pill_styles.rb` defines `PillStyles`, not `Styles::PillStyles`.

### Companion modules

A module named after a component with `Styles` appended is picked up without an `include`. Its traits, variables and theme merge straight into the component's own `styles` and `theme`, as if they had been declared in the class body, so the component's own declarations win on conflicts and combination traits can reference the module's traits. `ButtonComponent` looks for `ButtonComponentStyles`, and `Admin::ButtonComponent` looks for `Admin::ButtonComponentStyles`. The component still needs `include ViewComponent::Styles`.

```ruby
# app/components/toast_component_styles.rb
module ToastComponentStyles
  include ViewComponent::Styles

  styles do
    trait :root, display: :flex, gap: 6, padding: 12
  end
end

# app/components/toast_component.rb
class ToastComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    trait :cta, :root, font_weight: 700
  end

  erb_template <<~ERB
    <div <%= styles.props(styles.root) %>><%= content %></div>
  ERB
end

ToastComponent.styles.names  # => [:root, :cta]
```

The lookup is per class, so a subclass inherits its parent's companion and can add its own. A constant with the matching name that is not a style module is ignored.

### Plain Ruby constants

Everything a component can do, plain Ruby can do with `ViewComponent::Styles.create`. It takes a hash of traits, and each value follows the same shape rules as `trait`. A block with `trait` calls works too. The result is an ordinary sheet, so assign it to a constant and reference it from any view or component:

```ruby
# app/styles/card_styles.rb
module CardStyles
  CARD = ViewComponent::Styles.create(
    root:  { padding: 24, border_radius: 8, background: "#fff" },
    title: { font_size: 20, font_weight: 600 }
  )
end
```

```erb
<%# app/views/cards/show.html.erb %>
<div <%= sx(CardStyles::CARD.root) %>>
  <h2 <%= sx(CardStyles::CARD.title) %>><%= @card.title %></h2>
</div>
```

The same constants work inside a component template, with or without `include ViewComponent::Styles`:

```ruby
class CardComponent < ViewComponent::Base
  erb_template <<~ERB
    <div <%= sx(CardStyles::CARD.root) %>><%= content %></div>
  ERB
end
```

A module can hold both kinds: constants built with `create` alongside traits declared with `styles`. A module that only holds constants is not a style module, so including it in a component adds nothing beyond ordinary Ruby.

### Renaming `styles`

If `styles` clashes with something in your component, pick another name. `styles_method` renames both the class macro and the instance reader, and the old name is removed. Subclasses inherit the name.

```ruby
class PanelComponent < ViewComponent::Base
  include ViewComponent::Styles
  styles_method :css

  css do
    trait :root, padding: 24
  end

  erb_template <<~ERB
    <section <%= css.props(css.root) %>><%= content %></section>
  ERB
end

PanelComponent.css.root  # => Style
```

Set `config.view_component.styles.styles_method = :css` in an initializer to change the default for every component that includes the module afterwards.

A shared module that declares `styles_method :css` is exposed as `css` rather than under a derived accessor. If the component declares the same name, the two sheets merge into one and the component's traits win on conflicts. Only an explicit `styles_method` call inside the module counts, not the configured default.

```ruby
# app/styles/tag_styles.rb
module TagStyles
  include ViewComponent::Styles
  styles_method :css

  css do
    trait :tag, padding: 4
  end
end

# app/components/tag_component.rb
class TagComponent < ViewComponent::Base
  include TagStyles
  styles_method :css

  css do
    trait :label, font_weight: 600
  end

  erb_template <<~ERB
    <span <%= css.props(css.tag, css.label) %>><%= content %></span>
  ERB
end

TagComponent.css.names  # => [:tag, :label]
```

## Theming

Theming is two separate ideas:

- **Variables** are CSS custom properties. You declare them once with a default value, and styles reference them by name instead of hard-coding the value.
- **Themes** are overrides. A theme is a `Style` whose single class sets different values for some variables. Put it on a wrapper with `styles.props` and every descendant that reads those variables picks up the new values through the cascade.

Both come with `include ViewComponent::Styles`. Each is also available on its own: `include ViewComponent::Styles::Variables` gives you variables and the `styles` reader without traits, and `include ViewComponent::Styles::Theme` gives you `theme` and nothing else.

### Variables

Declare variables in a component with `style_vars`. They are read back through `styles`, alongside traits, and return a `var()` reference:

```ruby
class PanelComponent < ViewComponent::Base
  include ViewComponent::Styles

  style_vars gap: 12, accent: "#ff6600"

  styles do
    trait :root, display: "grid", gap: styles.gap, border_color: styles.accent
  end
end

PanelComponent.styles.gap        # => "var(--vcnbqr2vub)"
PanelComponent.styles.var_names  # => [:gap, :accent]
```

This emits `:root{--vcnbqr2vub:12px}` and `:root{--vclpsr1n9z:#ff6600}` in the stylesheet. Repeated `style_vars` calls merge, the block form defers evaluation like `styles do`, and subclasses inherit and can redeclare individual keys.

Rules for values:

- Values follow the same rules as style values. Numbers become `px`, so use a string for unitless numbers such as font weights.
- A hash value declares conditions the same way a property does inside a trait: `default` plus any pseudo-class symbol, breakpoint, or raw `@media` string. Only at-rules make sense on `:root`.
- Variable names are hashed from the declaring class or file and the key. Pass `name:` to hash from a stable string instead.

### App-wide variables

Variables shared across the app live in a plain Ruby file and are built with `define_vars`:

```ruby
# app/styles/brand.rb
module Brand
  VARS = ViewComponent::Styles.define_vars(
    primary: "#0055ff",
    surface: { default: "#fff", dark: "#111" },
    weight: "600"
  )
end
```

```ruby
# config/application.rb or an initializer
config.view_component.styles.vars = -> { Brand::VARS }
```

Once configured, every component's `styles` falls back to those variables, so `styles.primary` works in any component without declaring anything. A component's own `style_vars` shadow the configured ones. Outside components, read them from the constant or `ViewComponent::Styles.vars`.

The setting accepts a `Vars` object, a callable, or a constant name as a string. Prefer the callable or string form in an initializer, since `app/styles` is not loaded yet when initializers run.

### Themes

Declare a theme with `theme`. Keys resolve against the variables visible through `styles`: the component's own `style_vars` first, then the configured app-wide vars. Read it back with `theme` and apply it with `styles.props`:

```ruby
class PanelComponent < ViewComponent::Base
  include ViewComponent::Styles

  style_vars accent: "#ff6600"

  theme accent: "#00cc66", primary: "#000"

  styles do
    trait :root, border_color: styles.accent, color: styles.primary
  end

  erb_template <<~ERB
    <section <%= styles.props(theme, styles.root) %>><%= content %></section>
  ERB
end
```

The emitted CSS is one class per set of variables the theme touches, for example `.vccn09cvj7{--vclpsr1n9z:#00cc66}`. Everything inside the section that reads `accent` or `primary` now sees the new values. Nothing in the child components changes.

- Pass a `Vars` object first to target a specific set: `theme Brand::VARS, primary: "#000"`.
- Override values can be conditional hashes, so a theme can change a variable only under `dark` or a breakpoint.
- Unknown keys raise `KeyError` when the theme is first read.
- `theme` with no declarations returns an empty style, so `styles.props(theme)` is always safe.
- Subclasses inherit the parent's theme and can override keys.
- Two themes for the same `Vars` set are mutually exclusive when merged, and the last one wins. Themes nest: an inner wrapper's theme overrides an outer one for its subtree.

For plain Ruby, `ViewComponent::Styles.create_theme(vars, **overrides)` builds the same `Style` from an explicit `Vars` object, and `vars.theme(**overrides)` is shorthand for it.

### Theme modules

Put a theme in a module to share it. Including the module in a component exposes the theme as `<name>_theme`, where the name is derived the same way as for shared style modules, so `Admin::DarkTheme` becomes `admin_dark_theme`. The component's own `theme` stays separate. A module that only includes `ViewComponent::Styles::Theme` has no variables of its own, so its keys resolve against the app-wide vars.

```ruby
# app/styles/dark_mode_theme.rb
module DarkModeTheme
  include ViewComponent::Styles::Theme

  theme surface: "#000", primary: "#99bbff"
end

class PanelComponent < ViewComponent::Base
  include ViewComponent::Styles
  include DarkModeTheme

  theme accent: "#00cc66"

  def initialize(dark: false)
    @dark = dark
  end

  erb_template <<~ERB
    <section <%= styles.props(@dark ? dark_mode_theme : theme, styles.root) %>><%= content %></section>
  ERB
end
```

A module named `DarkModeStyle` that declares both traits and a theme is exposed as `dark_mode_styles` and `dark_mode_theme`. A module that includes `ViewComponent::Styles::Variables` follows the styles rule: `BrandVars` is exposed as `brand_styles`. An anonymous module merges into the component's `theme` or `styles` instead.

### Dark mode and responsive variables

Because conditions live on the variable declaration, most dark mode work happens in `define_vars` or `style_vars` and components stay unaware of it:

```ruby
VARS = ViewComponent::Styles.define_vars(
  surface: { default: "#fff", dark: "#111" },
  text: { default: "#111", dark: "#eee" },
  gutter: { default: 16, md: 12 }
)
```

For a user-selectable theme rather than a media query, declare one theme module per option and apply the chosen one on `<body>` or a layout wrapper.

## Configuration

All options live under `config.view_component.styles`.

| Option | Default | Purpose |
| --- | --- | --- |
| `inline` | `true` outside production | Inline a `<style>` tag instead of linking the built file |
| `output_path` | `app/assets/builds/view_component_styles.css` | Where the build task writes |
| `breakpoints` | `{}` | Symbol keys usable as conditions app-wide; `breakpoints` inside a `styles` block adds or overrides per component |
| `pseudo_map` | see `Configuration::DEFAULT_PSEUDO_MAP` | Symbol to pseudo-class/at-rule mapping |
| `class_prefix` | `"vc"` | Prefix for generated class and variable names |
| `styles_method` | `:styles` | Name of the class macro and instance reader added by `include ViewComponent::Styles` |
| `eager_load_paths` | `["app/components", "app/components/styles", "app/styles"]` | Directories loaded before the first request in development |
| `use_layers` | `false` | Wrap output in `@layer` blocks ordered by priority |
| `vars` | `nil` | App-wide variables: a `Vars`, a callable returning one, or a constant name |

Only enable `use_layers` if your other CSS is layered too, since unlayered rules outrank every layered one.

## Differences from StyleX

- Class names are `vc` + 8 base36 characters of a SHA1, not StyleX's murmurhash, so output is not byte-compatible with a JavaScript StyleX build.
- Top-level pseudo-class and media keys are rejected. Nest conditions under the property.
- A trait cannot be named after a CSS property, and one whose name collides with a method on `Object` or the sheet must be read with `styles[:name]`.
- There is no static analysis. Any `create` call reachable by loading `app/` is included in the build, and calls inside ERB templates are not.

## Development

```
bundle install
bundle exec rspec
```

The dummy app in `spec/dummy` exercises the railtie, the inline and file modes, and the rake task.
