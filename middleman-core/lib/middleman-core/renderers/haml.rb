# frozen_string_literal: true

# Require gem
require 'haml'

# Require padrino-helpers now so that we get a chance to replace their renderer with ours in Tilt.
require 'padrino-helpers'

module SafeTemplate
  def render(*)
    super.html_safe
  end
end

::Tilt::HamlTemplate.include SafeTemplate

module Middleman
  module Renderers
    # Haml precompiles filters before the scope is even available,
    # thus making it impossible to pass our Middleman instance
    # in. So we have to resort to heavy hackery :(
    class HamlTemplate < ::Tilt::HamlTemplate
      def initialize(*args, &block)
        super

        @context = @options[:context] if @options.key?(:context)
      end

      def prepare; end

      def evaluate(scope, locals, &block)
        options = @options.dup
        options.delete(:lang)
        options.delete(:locale)
        options.merge!(filename: eval_file, line: line, context: @context || scope)
        if options.include?(:outvar)
          options[:buffer] = options.delete(:outvar)
          options[:save_buffer] = true
        end
        @engine = ::Haml::Engine.new(data, options)
        @engine.render(scope, locals, &block)
      end
    end

    # Haml Renderer
    class Haml < ::Middleman::Extension
      def initialize(app, options_hash = ::Middleman::EMPTY_HASH, &block)
        super

        if Object.const_defined?('::Haml::Options') # not available in haml 6
          ::Haml::Options.defaults[:context] = nil
          ::Haml::Options.send :attr_accessor, :context
        end
        ::Haml::TempleEngine.define_options context: nil if defined?(::Haml::TempleEngine)
        [::Haml::Filters::Sass, ::Haml::Filters::Scss, ::Haml::Filters::Markdown].each do |f|
          f.class_exec do
            def self.render_with_options(text, compiler_options)
              modified_options = options.dup
              modified_options[:context] = compiler_options[:context]

              text = template_class.new(nil, 1, modified_options) { text }.render
              super(text, compiler_options)
            end
          end
        end

        ::Tilt.prefer(::Middleman::Renderers::HamlTemplate, :haml)

        # Add haml helpers to context
        ::Middleman::TemplateContext.include ::Haml::Helpers
      end

      def add_exposed_to_context(context)
        super

        context.init_haml_helpers if context.respond_to?(:init_haml_helpers)
      end
    end
  end
end
