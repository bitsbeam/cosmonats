# Custom serializers

```ruby
module MessagePackSerializer
  def self.serialize(data) = MessagePack.pack(data)
  def self.deserialize(payload) = MessagePack.unpack(payload)
end

class FastStream
  include Cosmo::Stream
  options publisher: { serializer: MessagePackSerializer }
end
```
