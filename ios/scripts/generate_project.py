"""Deterministic, dependency-free Xcode project for the unsigned iPhone target."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
project = root / "Huevia.xcodeproj"
project.mkdir(exist_ok=True)
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value): return json.dumps(str(value))
objects = []
def obj(key, value): objects.append(f"{uid(key)} = {{ {value} }};"); return uid(key)
sources = sorted((root / "Core").glob("*.swift")) + sorted((root / "Huevia").glob("*.swift"))
resources = sorted((root / "Huevia" / "Resources").glob("*"))
asset = root / "Huevia" / "Assets.xcassets"
asset.mkdir(exist_ok=True)
(asset / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
resources.append(asset)
source_builds, resource_builds, references = [], [], []
for path in sources + resources:
    rel = path.relative_to(root).as_posix()
    kind = "sourcecode.swift" if path.suffix == ".swift" else "folder.assetcatalog" if path.suffix == ".xcassets" else "text.json" if path.suffix == ".json" else "image.jpeg"
    reference = obj("file:" + rel, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(rel)}; sourceTree = SOURCE_ROOT;")
    references.append(reference)
    build = obj("build:" + rel, f"isa = PBXBuildFile; fileRef = {reference};")
    (source_builds if path in sources else resource_builds).append(build)
product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Huevia.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj("products", f"isa = PBXGroup; children = ({product},); name = Products; sourceTree = \"<group>\";")
main = obj("main", f"isa = PBXGroup; children = ({','.join(references + [products])},); sourceTree = \"<group>\";")
def phase(name, isa, builds):
    entries = ','.join(builds) + (',' if builds else '')
    return obj(name, f"isa = {isa}; buildActionMask = 2147483647; files = ({entries}); runOnlyForDeploymentPostprocessing = 0;")
source_phase = phase("sources", "PBXSourcesBuildPhase", source_builds)
resource_phase = phase("resources", "PBXResourcesBuildPhase", resource_builds)
framework_phase = phase("frameworks", "PBXFrameworksBuildPhase", [])
def configs(name, target=False):
    items = []
    for mode in ("Debug", "Release"):
        settings = {
            "CLANG_ENABLE_MODULES": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SDKROOT": "iphoneos",
            "SWIFT_VERSION": "5.0", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        }
        if target:
            settings.update(PRODUCT_BUNDLE_IDENTIFIER="cc.huevia.ios", PRODUCT_NAME="$(TARGET_NAME)",
                INFOPLIST_FILE="Huevia/Info.plist", GENERATE_INFOPLIST_FILE="NO", CODE_SIGN_STYLE="Manual",
                CODE_SIGNING_ALLOWED="NO", CODE_SIGNING_REQUIRED="NO", DEVELOPMENT_TEAM="",
                TARGETED_DEVICE_FAMILY="1", SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SUPPORTS_MACCATALYST="NO",
                ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", MARKETING_VERSION="0.1.0", CURRENT_PROJECT_VERSION="3",
                SWIFT_EMIT_LOC_STRINGS="YES", ENABLE_PREVIEWS="YES")
        fields = ' '.join(f'{k} = {quoted(v)};' for k, v in settings.items())
        items.append(obj(name + mode, f"isa = XCBuildConfiguration; buildSettings = {{ {fields} }}; name = {mode};"))
    return obj(name + "list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(items)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target_configs, project_configs = configs("target", True), configs("project")
target = obj("target", f"isa = PBXNativeTarget; buildConfigurationList = {target_configs}; buildPhases = ({source_phase},{framework_phase},{resource_phase},); buildRules = (); dependencies = (); name = Huevia; productName = Huevia; productReference = {product}; productType = \"com.apple.product-type.application\";")
root_id = obj("project", f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN,en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target},);")
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(objects) + f"\n}}; rootObject = {root_id}; }}\n", encoding="utf-8")
schemes = project / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Huevia.app" BlueprintName="Huevia" ReferencedContainer="container:Huevia.xcodeproj"/>'
(schemes / "Huevia.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding="utf-8")
print(f"Generated Huevia.xcodeproj: {len(sources)} Swift files, {len(resources)} resource entries")
