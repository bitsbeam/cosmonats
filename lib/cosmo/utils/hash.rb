# frozen_string_literal: true

module Cosmo
  module Utils
    module Hash
      module_function

      def symbolize_keys!(obj)
        case obj
        when ::Hash
          obj.keys.each do |key|
            raise ArgumentError, "key cannot be converted to symbol" unless key.respond_to?(:to_sym)

            sym = key.to_sym
            value = obj.delete(key)
            obj[sym] = symbolize_keys!(value)
          end
          obj
        when ::Array
          obj.map! { |v| symbolize_keys!(v) }
        else
          obj
        end
      end

      def stringify_keys(obj)
        case obj
        when ::Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_s] = stringify_keys(value)
          end
        when ::Array
          obj.map { |v| stringify_keys(v) }
        else
          obj
        end
      end

      # deep set
      def set(hash, *keys, value)
        last_key = keys.pop
        target = keys.reduce(hash) do |base, key|
          base[key] ||= {}
          base[key]
        end
        target[last_key] = value
      end

      # Nested hashes merge recursively, +other+ winning; any other value in +other+ replaces the one in +base+.
      #
      # @param base [::Hash]
      # @param other [::Hash]
      # @return [::Hash] a new hash
      def deep_merge(base, other)
        base.merge(other) { |_, old, new| old.is_a?(::Hash) && new.is_a?(::Hash) ? deep_merge(old, new) : new }
      end

      # deep dup
      def dup(hash)
        Marshal.load(Marshal.dump(hash))
      end
    end
  end
end
