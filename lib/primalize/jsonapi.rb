require 'primalize/jsonapi/version'
require 'primalize/single'

module Primalize
  module JSONAPI
    @model_type_cache = {}
    @serializer_map = {}

    class Relationships
      def initialize
        @rels = []
        @map = {}
      end

      def << rel
        @rels << rel
        @map[rel.attr] = rel
      end

      def [] rel
        @map[rel]
      end

      def metadata(model, cache:)
        @rels.each_with_object({}) do |rel, hash|
          hash[rel.attr] = rel.metadata(model, cache: cache)
        end
      end

      def call(model, cache:)
        @rels.each_with_object({}) do |rel, hash|
          hash[rel.attr] = rel.call(model)
        end
      end
    end

    class HasMany
      attr_reader :attr
      def initialize attr, type: attr, &block
        @attr = attr
        @block = block || proc { JSONAPI.fetch(type) }
      end

      def call(model, cache:)
        model.send(@attr).map do |obj|
          cache.fetch(:serialization, obj) do
            primalizer.new(obj).call
          end
        end
      end

      def primalizer
        @primalizer ||= @block.call
      end

      def metadata(model, cache:)
        result = model.send(@attr).map do |obj|
          cache.fetch(:metadata, obj) do
            MetadataPrimalizer.new(obj, primalizer.type).call
          end
        end

        { data: result }
      end
    end

    class HasOne
      attr_reader :attr
      def initialize attr, type: attr, &block
        @attr = attr
        @block = block || proc { JSONAPI.fetch(type) }
      end

      def call(model, cache:)
        model = model.send(@attr)
        cache.fetch(:serialization, model) do
          primalizer.new(model).call
        end
      end

      def primalizer
        @primalizer ||= @block.call
      end

      def metadata(model, cache:)
        model = model.send(@attr)
        cache.fetch(:metadata, model) do
          { data: MetadataPrimalizer.new(model, primalizer.type).call }
        end
      end
    end

    class MetadataPrimalizer < Single
      attributes(id: string(&:to_s), type: string)

      attr_reader :type

      def initialize model, type
        super model
        @type = type.to_s
      end
    end

    class Cache
      def initialize
        # Three-layer cache: metadata/serialization, class, and id
        @cache = Hash.new do |h, k|
          h[k] = Hash.new do |h, k|
            h[k] = {}
          end
        end
      end

      def [] type, model
        return if model.nil?

        @cache[type][model.class][model.id]
      end

      def []= type, model, value
        return if model.nil?

        @cache[type][model.class][model.id] = value
      end

      def fetch type, model
        return if model.nil?

        @cache[type][model.class][model.id] ||= yield
      end
    end

    def self.[]= type, serializer
      @serializer_map[type] = serializer
    end

    def self.fetch type
      @serializer_map.fetch type do
        raise ArgumentError, "No Primalize::JSONAPI primalizer defined for #{type.inspect}"
      end
    end

    def self.[] type=nil, **options
      @serializer_map[type] ||= Class.new(Single) do
        @_type = type

        # This is useful for situations like this:
        #   class MySerializer < Primalize::JSONAPI[:movies]
        #   end
        define_singleton_method :inherited do |inheriting_class|
          JSONAPI[type] = inheriting_class
        end

        def self.type
          if @_type
            @_type
          else
            superclass.type
          end
        end

        def self.model_primalizer
          original_primalizer = self

          @model_primalizer ||= Class.new(Single) do
            def self.attributes **attrs
              attribute_primalizer.attributes attrs
            end

            define_singleton_method :to_s do
              "#{original_primalizer}.model_primalizer"
            end
            define_singleton_method(:name) { to_s }

            define_singleton_method :attribute_primalizer do
              @attribute_primalizer ||= Class.new(Single) do
                def initialize model, original:
                  super model
                  @original = original
                end

                def self.attributes(**attrs)
                  super

                  attrs.each do |attr, type|
                    define_method attr do
                      if @original.respond_to? attr
                        @original.public_send attr
                      else
                        object.public_send attr
                      end
                    end
                  end
                end

                define_singleton_method :to_s do
                  "#{original_primalizer}.model_primalizer.attribute_primalizer"
                end

                define_singleton_method(:name) { to_s }
              end
            end

            def self.relationships
              @relationships ||= Relationships.new
            end

            def self.has_many *args, &block
              relationships << HasMany.new(*args, &block)
            end

            def self.has_one *args, &block
              relationships << HasOne.new(*args, &block)
            end

            _attributes(
              id: string(&:to_s),
              type: string,
              attributes: object,
              relationships: object,
            )

            attr_reader :cache

            def initialize model, original:, cache: Cache.new
              super model
              @original = original
              @cache = cache
            end

            define_method :type do
              original_primalizer.type.to_s
            end

            def attributes
              self.class.attribute_primalizer.new(object, original: @original).call
            end

            def relationships
              self.class.relationships.metadata object, cache: cache
            end
          end
        end

        def self.attributes **attrs
          model_primalizer.attributes attrs
        end

        _attributes data: array(primalize(model_primalizer))

        def self.has_many *args, &block
          model_primalizer.has_many *args, &block
        end

        def self.has_one *args, &block
          model_primalizer.has_one *args, &block
        end

        attr_reader :cache

        def initialize models, include: [], meta: nil, cache: Cache.new
          super Array(models)

          @include = include
          @meta = meta
          @cache = cache
        end

        def call
          super.tap do |value|
            if @meta
              value[:meta] = @meta
            end

            unless @include.to_a.empty?
              included = Set.new

              @include.each do |rel|
                object.each do |model|
                  primalizer = self.class.model_primalizer.relationships[rel]
                  relationship = primalizer.call(model, cache: cache)

                  case relationship
                  when Array
                    relationship.each do |object|
                      object[:data].each do |data|
                        data.delete :relationships
                        included << data
                      end
                    end
                  when Hash
                    data = relationship[:data].first
                    data.delete :relationships
                    included << data
                  end
                end
              end

              value[:included] = included.to_a
            end
          end
        end

        def data
          object.map do |model|
            self.class.model_primalizer.new(model, original: self, cache: cache).call
          end
        end
      end
    end
  end
end
