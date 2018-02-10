require 'primalize/jsonapi/version'
require 'primalize/single'
require 'primalize/many'

module Primalize
  module JSONAPI
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
      def initialize attr, &block
        @attr = attr
        @block = block
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
            MetadataPrimalizer.new(obj).call
          end
        end

        { data: result }
      end
    end

    class HasOne
      attr_reader :attr
      def initialize attr, &block
        @attr = attr
        @block = block
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
          { data: MetadataPrimalizer.new(model).call }
        end
      end
    end

    class MetadataPrimalizer < Single
      attributes(id: string(&:to_s), type: string)

      def type
        object.class.name.gsub(/(.)([A-Z])/, '\1_\2').downcase
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
        @cache[type][model.class][model.id]
      end

      def []= type, model, value
        @cache[type][model.class][model.id] = value
      end

      def fetch type, model
        @cache[type][model.class][model.id] ||= yield
      end
    end

    def self.[] *args
      Class.new(Single) do
        def self.model_primalizer
          @model_primalizer ||= Class.new(Single) do
            def self.attributes **attrs
              attribute_primalizer.attributes attrs
            end

            def self.attribute_primalizer
              @attribute_primalizer ||= Class.new(Single) do
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

            def initialize model, cache: Cache.new
              super(model)
              @cache = cache
            end

            def self.name
              'ModelPrimalizer'
            end

            def type
              object.class.name.gsub(/(.)([A-Z])/, '\1_\2').downcase
            end

            def attributes
              self.class.attribute_primalizer.new(object).call
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
            self.class.model_primalizer.new(model, cache: cache).call
          end
        end
      end
    end
  end
end
