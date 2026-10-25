# Remake Color struct with float instead of double and make it support simd
ok using Double in color starts to show tooo much downsides and we are constant
repacking Double to Float to pass to shader..


# make it support SIMD
instead of trying to wrap around SIMD4<Float> we should just make it conform and work as SIMD4
codeblock was just to see what see what it wanted to be filled out, and ofc needs to be done right now..

```swift
public struct Color: Hashable, Sendable, SIMD {
    public subscript(index: Int) -> Float {
        get {
            fatalError()
        }
        set {
            fatalError()
        }
    }
    
    public init() {
        
    }
    
    public typealias MaskStorage = SIMD4<Int32>
    
    public typealias ArrayLiteralElement = Float
    
    public typealias Scalar = Float
    
    
    public var scalarCount: Int { 4 }
    
    public init(arrayLiteral elements: Float...) {
        
    }
}
```

# fix places using old color
find old double casting stuff of color, and other simd translations since it should now work
directly with other simd / float values...

all examples needs fixing 2... but make sure main lib demo etc builds and runs first.. 

# what to avoid now
we shouldnt now need todo this anymore

```swift
data.append(contentsOf: [Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha)])
```

or when packing the structures to bytes by ShaderValue protocol
we should now just be able to get the bytes directly now...
