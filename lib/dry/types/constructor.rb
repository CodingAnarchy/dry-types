# frozen_string_literal: true

require 'dry/types/fn_container'
require 'dry/types/constructor/function'

module Dry
  module Types
    # Constructor types apply a function to the input that is supposed to return
    # a new value. Coercion is a common use case for constructor types.
    #
    # @api public
    class Constructor < Nominal
      include Dry::Equalizer(:type, :options, inspect: false)

      # @return [#call]
      attr_reader :fn

      # @return [Type]
      attr_reader :type

      undef :constrained?, :meta

      # @param [Builder, Object] input
      # @param [Hash] options
      # @param [#call, nil] block
      #
      # @api public
      def self.new(input, **options, &block)
        type = input.is_a?(Builder) ? input : Nominal.new(input)
        super(type, **options, fn: Function[options.fetch(:fn, block)])
      end

      # Instantiate a new constructor type instance
      #
      # @param [Type] type
      # @param [Function] fn
      # @param [Hash] options
      #
      # @api private
      def initialize(type, fn: nil, **options)
        @type = type
        @fn = fn

        super(type, **options, fn: fn)
      end

      # Return the inner type's primitive
      #
      # @return [Class]
      #
      # @api public
      def primitive
        type.primitive
      end

      # Return the inner type's name
      #
      # @return [String]
      #
      # @api public
      def name
        type.name
      end

      # @return [Boolean]
      #
      # @api public
      def default?
        type.default?
      end

      # @return [Object]
      #
      # @api private
      def call_safe(input)
        coerced = fn.(input) { |output = input| return yield(output) }
        type.call_safe(coerced) { |output = coerced| yield(output) }
      end

      # @return [Object]
      #
      # @api private
      def call_unsafe(input)
        type.call_unsafe(fn.(input))
      end

      # @param [Object] input
      # @param [#call,nil] block
      #
      # @return [Logic::Result, Types::Result]
      # @return [Object] if block given and try fails
      #
      # @api public
      def try(input, &block)
        value = fn.(input)
      rescue CoercionError => e
        failure = failure(input, e)
        block_given? ? yield(failure) : failure
      else
        type.try(value, &block)
      end

      # Build a new constructor by appending a block to the coercion function
      #
      # @param [#call, nil] new_fn
      # @param [Hash] options
      # @param [#call, nil] block
      #
      # @return [Constructor]
      #
      # @api public
      def constructor(new_fn = nil, **options, &block)
        with({**options, fn: fn >> (new_fn || block)})
      end
      alias_method :append, :constructor
      alias_method :>>, :constructor

      # @return [Class]
      #
      # @api private
      def constrained_type
        Constrained::Coercible
      end

      # @see Nominal#to_ast
      #
      # @api public
      def to_ast(meta: true)
        [:constructor, [type.to_ast(meta: meta), fn.to_ast]]
      end

      # Build a new constructor by prepending a block to the coercion function
      #
      # @param [#call, nil] new_fn
      # @param [Hash] options
      # @param [#call, nil] block
      #
      # @return [Constructor]
      #
      # @api public
      def prepend(new_fn = nil, **options, &block)
        with({**options, fn: fn << (new_fn || block)})
      end
      alias_method :<<, :prepend

      # Build a lax type
      #
      # @return [Lax]
      # @api public
      def lax
        Lax.new(Constructor.new(type.lax, options))
      end

      # Wrap the type with a proc
      #
      # @return [Proc]
      #
      # @api public
      def to_proc
        proc { |value| self.(value) }
      end

      private

      # @param [Symbol] meth
      # @param [Boolean] include_private
      # @return [Boolean]
      #
      # @api private
      def respond_to_missing?(meth, include_private = false)
        super || type.respond_to?(meth)
      end

      # Delegates missing methods to {#type}
      #
      # @param [Symbol] method
      # @param [Array] args
      # @param [#call, nil] block
      #
      # @api private
      def method_missing(method, *args, &block)
        if type.respond_to?(method)
          response = type.public_send(method, *args, &block)

          if response.is_a?(Type) && type.class == response.class
            response.constructor_type.new(response, options)
          else
            response
          end
        else
          super
        end
      end
    end
  end
end
