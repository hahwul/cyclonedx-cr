require "spec"
require "../../src/cyclonedx/bom"

# Validates generated CycloneDX XML against the official CycloneDX XSD schemas
# (vendored under spec/schemas/) using `xmllint`. This is the safety net for the
# whole class of element-ordering / structure / required-attribute bugs that
# string-matching specs cannot catch. When `xmllint` is unavailable the examples
# are skipped (pending) so the suite still runs locally without it.

private XMLLINT    = Process.find_executable("xmllint")
private SCHEMA_DIR = File.expand_path(File.join(__DIR__, "..", "schemas"))

# Runs xmllint against the bundled bom-<version>.xsd and returns {success, stderr}.
private def xsd_validate(xml : String, version : String) : {Bool, String}
  xsd = File.join(SCHEMA_DIR, "bom-#{version}.xsd")
  catalog = File.join(SCHEMA_DIR, "catalog.xml")
  tmp = File.tempfile("cdx-schema", ".xml")
  begin
    File.write(tmp.path, xml)
    err = IO::Memory.new
    status = Process.run(
      "xmllint", ["--noout", "--schema", xsd, tmp.path],
      env: {"XML_CATALOG_FILES" => catalog},
      output: Process::Redirect::Close, error: err)
    {status.success?, err.to_s}
  ensure
    tmp.delete
  end
end

# A BOM shaped like the actual CLI output: metadata.component (application) plus
# library components, dependencies, and external references.
private def cli_bom(version : String) : CycloneDX::BOM
  licenses = [CycloneDX::License.new(id: "MIT")] of CycloneDX::License | CycloneDX::LicenseExpression
  ext = [CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/o/root")]
  root = CycloneDX::Component.new(
    name: "root", version: "1.0.0", component_type: "application", bom_ref: "root@1.0.0",
    description: "d", author: "a", licenses: licenses, external_references: ext)
  metadata = CycloneDX::Metadata.new(component: root, timestamp: "2024-01-01T00:00:00Z",
    tools: [CycloneDX::Tool.new(vendor: "hahwul", name: "cyclonedx-cr", version: "1.0")])
  components = [
    CycloneDX::Component.new(name: "dep", version: "2.0.0", bom_ref: "dep@2.0.0",
      purl: "pkg:github/o/dep@2.0.0", scope: "required"),
  ]
  deps = [
    CycloneDX::Dependency.new(ref: "root@1.0.0", depends_on: ["dep@2.0.0"]),
    CycloneDX::Dependency.new(ref: "dep@2.0.0"),
  ]
  CycloneDX::BOM.new(spec_version: version, metadata: metadata, components: components, dependencies: deps)
end

# A maximally-populated BOM exercising every library model type's serializer.
private def rich_bom(version : String) : CycloneDX::BOM
  org = CycloneDX::OrganizationalEntity.new(name: "Acme", url: ["https://acme.example"],
    contact: [CycloneDX::OrganizationalContact.new(name: "Jane", email: "j@acme.example")])
  contact = CycloneDX::OrganizationalContact.new(name: "Bob", email: "b@x.example")
  extref = CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com",
    comment: "c", hashes: [CycloneDX::Hash.new(algorithm: "SHA-256", content: "a" * 64)])
  prop = CycloneDX::Property.new(name: "k", value: "v")

  lic_id = CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "declared")
  lic_named = CycloneDX::License.new(name: "Custom",
    text: CycloneDX::AttachedText.new(content: "abc", content_type: "text/plain", encoding: "base64"))
  lic_expr = CycloneDX::LicenseExpression.new(expression: "MIT OR Apache-2.0", bom_ref: "le-1")

  evidence = CycloneDX::Evidence.new(
    identity: [CycloneDX::EvidenceIdentity.new(field: "name", confidence: 0.9,
      methods: [CycloneDX::EvidenceMethod.new(technique: "source-code-analysis", confidence: 0.8)])],
    occurrences: [CycloneDX::EvidenceOccurrence.new(location: "/a"), CycloneDX::EvidenceOccurrence.new(location: "/b")],
    licenses: [lic_named] of CycloneDX::License | CycloneDX::LicenseExpression,
    copyright: [CycloneDX::EvidenceCopyright.new(text: "c1"), CycloneDX::EvidenceCopyright.new(text: "c2")])
  pedigree = CycloneDX::Pedigree.new(notes: "n",
    commits: [CycloneDX::Commit.new(uid: "u", url: "https://c.example", message: "m")],
    patches: [CycloneDX::Patch.new(patch_type: "unofficial")])
  swid = CycloneDX::Swid.new(tag_id: "swid-1", name: "sw", version: "1", tag_version: 2, patch: false)
  rn = CycloneDX::ReleaseNotes.new(release_type: "major", title: "t", description: "d",
    timestamp: "2024-01-01T00:00:00Z", aliases: ["a1"], tags: ["t1"], properties: [prop])
  crypto = CycloneDX::CryptoProperties.new(asset_type: "algorithm",
    algorithm_properties: CycloneDX::AlgorithmProperties.new(primitive: "signature", crypto_functions: ["sign"]),
    oid: "1.2.3")

  main = CycloneDX::Component.new(
    name: "root", version: "1.0.0", component_type: "application", bom_ref: "root@1.0.0",
    mime_type: "application/json", group: "g", scope: "required",
    purl: "pkg:github/o/root@1.0.0", cpe: "cpe:2.3:a:o:root:1.0.0:*:*:*:*:*:*:*",
    description: "desc", author: "auth", publisher: "pub", copyright: "cp",
    supplier: org, manufacturer: org,
    licenses: [lic_id, lic_named] of CycloneDX::License | CycloneDX::LicenseExpression,
    hashes: [CycloneDX::Hash.new(algorithm: "SHA-512", content: "b" * 128)],
    external_references: [extref], properties: [prop],
    tags: ["t1"], omnibor_id: ["gitoid:blob:sha256:abc"], swhid: ["swh:1:cnt:abc"],
    pedigree: pedigree, evidence: evidence, authors: [contact], swid: swid, release_notes: rn,
    crypto_properties: crypto,
    components: [CycloneDX::Component.new(name: "sub", version: "0.1", bom_ref: "sub@0.1",
      licenses: [lic_expr] of CycloneDX::License | CycloneDX::LicenseExpression)])

  metadata = CycloneDX::Metadata.new(component: main, timestamp: "2024-01-01T00:00:00Z",
    tools: [CycloneDX::Tool.new(vendor: "v", name: "n", version: "1")],
    authors: [contact], properties: [prop],
    lifecycles: [CycloneDX::Lifecycle.new(phase: "build")], supplier: org)

  service = CycloneDX::Service.new(name: "svc", version: "1", bom_ref: "svc-1",
    provider: org, group: "g", description: "d", endpoints: ["https://api.example"],
    authenticated: true, x_trust_boundary: true, trust_zone: "tz",
    data: [CycloneDX::DataClassification.new(flow: "inbound", classification: "public")],
    licenses: [lic_named] of CycloneDX::License | CycloneDX::LicenseExpression,
    external_references: [extref], properties: [prop],
    services: [CycloneDX::Service.new(name: "subsvc", bom_ref: "subsvc-1")],
    tags: ["t1"], release_notes: rn)

  vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", bom_ref: "vuln-1",
    source: CycloneDX::VulnerabilitySource.new(name: "NVD", url: "https://nvd.example"),
    references: [CycloneDX::VulnerabilityReference.new(id: "GHSA-x",
      source: CycloneDX::VulnerabilitySource.new(name: "GH", url: "https://gh.example"))],
    ratings: [CycloneDX::VulnerabilityRating.new(score: 7.5, severity: "high", method: "CVSSv3")],
    cwes: [79, 89], description: "d", detail: "det", recommendation: "rec", workaround: "wa",
    proof_of_concept: CycloneDX::ProofOfConcept.new(reproduction_steps: "rs",
      supporting_material: [CycloneDX::AttachedText.new(content: "x")]),
    advisories: [CycloneDX::Advisory.new(url: "https://adv.example", title: "adv")],
    created: "2024-01-01T00:00:00Z", published: "2024-01-02T00:00:00Z",
    updated: "2024-01-03T00:00:00Z", rejected: "2024-01-04T00:00:00Z",
    credits: CycloneDX::Credits.new(organizations: [org], individuals: [contact]),
    tools: [CycloneDX::Tool.new(name: "scanner")],
    analysis: CycloneDX::VulnerabilityAnalysis.new(state: "exploitable",
      justification: "code_not_reachable", response: ["will_not_fix"],
      first_issued: "2024-01-01T00:00:00Z", last_updated: "2024-01-02T00:00:00Z"),
    affects: [CycloneDX::VulnerabilityAffect.new(ref: "root@1.0.0",
      versions: [CycloneDX::AffectedVersion.new(version: "1.0.0", status: "affected")])],
    properties: [prop])

  composition = CycloneDX::Composition.new(aggregate: "complete", bom_ref: "comp-1",
    assemblies: ["root@1.0.0"], dependencies: ["dep@2.0"], vulnerabilities: ["vuln-1"])
  annot = CycloneDX::Annotation.new(bom_ref: "ann-1", subjects: ["root@1.0.0"],
    annotator: CycloneDX::Annotator.new(organization: org), timestamp: "2024-01-01T00:00:00Z", text: "note")
  formula = CycloneDX::Formula.new(bom_ref: "formula-1",
    workflows: [CycloneDX::Workflow.new(bom_ref: "wf-1", uid: "wf-uid", name: "w", task_types: ["build"],
      tasks: [CycloneDX::Task.new(bom_ref: "task-1", uid: "task-uid", name: "t", task_types: ["build"],
        steps: [CycloneDX::TaskStep.new(name: "s",
          commands: [CycloneDX::StepCommand.new(executed: "echo hi")])])])])
  declarations = CycloneDX::Declarations.new(
    claims: [CycloneDX::Claim.new(bom_ref: "claim-1", target: "root@1.0.0", predicate: "p",
      mitigation_strategies: ["m"], reasoning: "r", evidence: ["ev-1"])])
  definitions = CycloneDX::Definitions.new(standards: [
    CycloneDX::DefinitionStandard.new(bom_ref: "std-1", name: "NIST", version: "1.1",
      description: "SSDF", owner: "NIST",
      requirements: [CycloneDX::DefinitionRequirement.new(bom_ref: "req-1", identifier: "R1", title: "T")]),
  ])

  CycloneDX::BOM.new(spec_version: version, metadata: metadata,
    components: [CycloneDX::Component.new(name: "dep", version: "2.0", bom_ref: "dep@2.0",
      purl: "pkg:github/o/dep@2.0", scope: "optional")],
    dependencies: [CycloneDX::Dependency.new(ref: "root@1.0.0", depends_on: ["dep@2.0"]),
                   CycloneDX::Dependency.new(ref: "dep@2.0")],
    properties: [prop], vulnerabilities: [vuln], services: [service], compositions: [composition],
    annotations: [annot], formulation: [formula], declarations: declarations,
    definitions: definitions, external_references: [extref])
end

describe "CycloneDX XSD schema validation" do
  ["1.4", "1.5", "1.6"].each do |version|
    it "emits XSD-valid XML for a CLI-shaped BOM (spec #{version})" do
      pending!("xmllint not installed") unless XMLLINT
      ok, err = xsd_validate(cli_bom(version).to_xml, version)
      fail("bom-#{version}.xsd validation failed:\n#{err}") unless ok
      ok.should be_true
    end
  end

  it "emits XSD-valid XML for a fully-populated library BOM (spec 1.6)" do
    pending!("xmllint not installed") unless XMLLINT
    ok, err = xsd_validate(rich_bom("1.6").to_xml, "1.6")
    fail("rich BOM bom-1.6.xsd validation failed:\n#{err}") unless ok
    ok.should be_true
  end
end
