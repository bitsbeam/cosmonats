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

      # deep set
      def set(hash, *keys, value)
        last_key = keys.pop
        target = keys.reduce(hash) do |base, key|
          base[key] ||= {}
          base[key]
        end
        target[last_key] = value
      end

      # deep dup
      def dup(hash)
        Marshal.load(Marshal.dump(hash))
      end
    end
  end
end
