# New Generic ShaderFunctions concept

up until now it made sense with this Single ShaderFunction and the ShaderArgument enum to solve.

i just feel there is a few downsides with constant having to pass all the enums over n over 
it also does we cant introduce new Argument types either.. 
and as i understand it our values needs to be packed into bytes no matter whwt that we send to gpu/vulkan
soo this whole thing with packing all into [Float] first doesnt seems to be a smart choice either..

also we need to decide if [UInt8] or Data but since the c / c++ side of Vulkan knows jack shit of 
Data, i assume [Uint8] is more neutral.. and doesnt envolve Foundation usage directly..


```swift
public protocol ShaderValue {
    func pack(into data: inout Data) // not sure if we should rely on Data or [UInt8]
    func pack(into bytes: inout [UInt8])
}

extension ShaderValue {
    public static var memorySize: Int { MemoryLayout<Self>.size }
    public static var memoryStride: Int { MemoryLayout<Self>.stride }
    
    public func pack(into data: inout Data) {
        withUnsafeBytes(of: self) { raw in
            data.append(contentsOf: raw)
        }
    }
    // just add a default handle of it, and then the type can choose to
    // add own version of it, if pack needs different way of adding the byte
    // if alignment issues of the memory, and needs some more explicit way of handling the bytes
    public func pack(into bytes: inout [UInt8]) {
        withUnsafeBytes(of: self) { raw in
            bytes.append(contentsOf: raw)
        }
    }
}
```

# Observable class based arguments

```swift
public protocol ShaderInput: Observable, AnyObject {
    
}
```

the ShaderFunction(any of them) using ShaderProtocol, should just be able to detect based on Observation
when a argument value changes..

whatever existing code using current ShaderFunction / ShaderArgument enum should i guess still be up 2 the View containing it how that updates based on the enums arguments
but it should just be so an datamodel can pass some ShaderInput based class that makes the ShaderFunction update internal when needed, 
and doesnt have to go through the whole View tree by default...


# what todo with existing ShaderFunction and argument for it..

for now keep old ShaderFunction and so on.. 

i dont want to break compatebility completely for now
and old ShaderFunction would just need to confirm to ShaderProtocol
and ShaderArgument conforms to ShaderValue for now... 


make ShaderView generic to ShaderProtocol now also.. 


# NucleantUI_PyShader package/repo
we shouldnt bind PyShader to NucleantUI anymore, our ShaderProtocol is neutral to [UInt32], and instead introduce NucleantUI_PyShader package
and then inside we example got PyShaderFunction, but that is still generic to ShaderInput / ShaderValue
but this one focuses on PyShader Strings directly...

we have also introduced BuildTool / CommandTool plugins which can precompile pyshader files into spirv files..
so PyShaderFunction should just be for when using direct .py / or strings.. 
else we should just use the default Shaderfunctions being added to NucleantUI..
Examples/ other Apps should also instead now just add PyShader / NucleantUI_PyShader themself when dealing with pyshader code..


# default Spirv ShaderFunction
maybe make one SpirvFunction by default, incase user just want to use direct spirv code, without having to make one them self, besides our existing ShaderFunction



# better integration with RenderTexture
claude in another library tried using the

```swift
let tex = renderTexture() { ShaderFunction(...) }
```
which results in empty pixels which i also explained to it, doing like that doesnt make much sense, also complicated to fill in arguments each time..
and i still stand by this shouldnt be done like this.. and user still needs to introduce a view struct that holds it for it to work in renderTexture..
what we should do is allow ShaderProtocol to have this 

```swift
// maybe better if its a class based protocol ?
public protocol ShaderProtocol {
    ...
    
    var renderTexture: RenderTexture { get }
    
    func render(into tex: RenderTexture)
}
```
that can just take the ShaderNode VkImage and just copy content to the image in RenderTexture, for low overhead render to the texture
and either create new by renderTexture var, or update existing with render function

since ShaderInput protocol can be observed for changes

we can just do in a datamodel 
```swift
myShader.observe { [weak self] shader in // called when ShaderInputs changes
    guard let self else { return }
    shader.render(into: self.myTex)
}
```


# ShaderArgumentsBuilder

explore the idea we can also create a ShaderInput by resultbuilder
and should just result in example "some ShaderInput"
maybe add 3 default classes for ShaderInput

ShaderNoArguments - speaks for itself
ShaderSingleArgument - speaks for itself
ShaderTupleArguments - like TupleView and all data packing is handled by parameter packs

```
@ShaderArgumentsBuilder ..... {
    30.0 // we entered a constant
    myType.floatValue // also just constant
    myType.color // same
    
    myObservedColor // some observation based class that conforms to ShaderValue, this should now be observed 
    myObservedClass.color // the class itself is observable, soo should just be able to observe when .color changes
    
    myType.someValue // the type is using example touchbayui ObservableValue<Float>, this can also be observed..
    // should just be a question of ShaderArgumentsBuilder got a case for where T: ShaderValue & Observable
    // again Generics handled right and it should be easy without having to introduce 2000 new layers.. 
    
}

but should also allow 

```swift
// example when TouchBayUI uses it
extension ObservableValue: ShaderValue {
    
}

# what to avoid doing now

this was fine todo since we only hat one ShaderFunction to handle everything, but this shouldnt be required now...
```swift
    /// Whether this function places its own geometry — a `glslVertexStage`,
    /// or a `def vertex` beside a `def fragment` in one PyShader module. The
    /// host draws it with a graphics pipeline rather than a compute dispatch,
    /// and it is the same `ShaderFunction` either way, so `.shader(_:)` takes
    /// it as it takes any other.
    public var isGraphics: Bool {
        switch language {
        case .glsl:
            return glslVertexStage != nil
        case .pyshader:
            return Self.definesStage("vertex", in: body) && Self.definesStage("fragment", in: body)
        case .spirv:
            // One module, one entry point — see `init(spirv:)`.
            return false
        }
    }

    /// `def <name>(` at the start of a line of PyShader source.
    static func definesStage(_ name: String, in source: String) -> Bool {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.drop(while: { $0 == " " || $0 == "\t" })
            guard text.hasPrefix("def ") else { continue }
            let rest = text.dropFirst(4).drop(while: { $0 == " " })
            if rest.hasPrefix(name), rest.dropFirst(name.count).drop(while: { $0 == " " }).hasPrefix("(") {
                return true
            }
        }
        return false
    }
```

solving it:

look into if PyShader can add info to SpirvBytecode that tells if 
shader is either just 
main - just fragment shader
fragment / vertex - if vertex function is present it should just know we both fragment + vertex



# PyShader - main / fragment accepting class as argument input 
when i say class i ofc mean what been done with pyshader converts class layout into structure in vulkan/spirv
but i dont get why when returning example glow in babylights experiment, has to be unpacked as seperate arguments in the fragment part
shouldnt there be a way just to pass the whole structure as type and then fragment reads type.x type.intensity type.level or whatever the 
class / structure defined..

and then in Swift we should be also to just make a struct or whatever on swift side, just pass that (ofc it must match the layout of class in python)


# What i dont want to happen now...

Claude doesnt seem to be very good with Generics + protocols
example this layout of protocols shouldnt require that claude now introduces 20000 new classes enums structs just to handle these protocols
and its a major issue when that happens, because its bad patterns of using Generics
while making a protocol based api is never easy because its hard to tell whwt it should contain, then doing it the right
should actually reduce the needs to all kinds of wrappers around it..



# moved types and where to work from now with Shader related stuff in NucleantUI

Float2,3,4 is moved to NucleantUI/Sources/NucleantUI/Shader
along with the mentioned protocols etc
and please make it more each new type == new file
