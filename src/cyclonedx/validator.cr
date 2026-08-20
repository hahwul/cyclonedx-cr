require "./bom"
require "./formulation"
require "./version_gate"

module CycloneDX
  class ValidationError
    getter path : String
    getter message : String

    def initialize(@path : String, @message : String)
    end

    # Defined as `to_s(io)` rather than a no-arg `to_s : String`: string
    # interpolation and `IO#<<` go through the IO form, so overriding only the
    # no-arg form left `"#{error}"` printing the default `#<ValidationError:0x…>`
    # while a direct `error.to_s` looked correct.
    def to_s(io : IO) : Nil
      io << @path << ": " << @message
    end
  end

  class Validator
    # Problems that make the serialized document invalid. `validate` fails on
    # these.
    getter errors : Array(ValidationError)

    # Places where the BOM was *valid but over-specified* for its declared
    # `specVersion`, and the version gate downgraded it on the way out: a field
    # stripped, an enum value swapped for its catch-all, a repeated element
    # collapsed. The output is schema-valid, so these do not fail `validate`, but
    # they are the record of what the declared version could not carry.
    getter warnings : Array(ValidationError)

    def initialize
      @errors = [] of ValidationError
      @warnings = [] of ValidationError
    end

    # `bom.serialNumber`. Both schema families constrain it to the same shape —
    # the JSON schemas with this exact regex and the XSDs with the `urnUuid`
    # pattern — so a prefix check is not enough: `urn:uuid:not-a-uuid` and an
    # upper-case UUID both pass "starts with 'urn:uuid:'" and are both rejected
    # by every official schema. Lower case is deliberate; the pattern is
    # `[0-9a-f]`, not `[0-9a-fA-F]`.
    SERIAL_NUMBER_PATTERN =
      /\Aurn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def validate(bom : BOM) : Bool
      @errors.clear
      @warnings.clear
      validate_bom(bom)
      @errors.empty?
    end

    private def validate_bom(bom : BOM)
      add_error("$.bomFormat", "must be 'CycloneDX'") unless bom.bom_format == "CycloneDX"
      add_error("$.specVersion", "must be a supported version") unless BOM::SUPPORTED_VERSIONS.includes?(bom.spec_version)
      unless bom.serial_number.matches?(SERIAL_NUMBER_PATTERN)
        add_error("$.serialNumber", "'#{bom.serial_number}' is not a 'urn:uuid:' RFC 4122 URN")
      end

      bom.components.each_with_index do |comp, i|
        validate_component(comp, "$.components[#{i}]")
      end

      if ext_refs = bom.external_references
        ext_refs.each_with_index do |ref, i|
          validate_external_reference(ref, "$.externalReferences[#{i}]")
        end
      end

      if svcs = bom.services
        svcs.each_with_index do |svc, i|
          validate_service(svc, "$.services[#{i}]")
        end
      end

      if vulns = bom.vulnerabilities
        vulns.each_with_index do |vuln, i|
          validate_vulnerability(vuln, "$.vulnerabilities[#{i}]")
        end
      end

      if comps = bom.compositions
        comps.each_with_index do |comp, i|
          validate_composition(comp, "$.compositions[#{i}]")
        end
      end

      if formulas = bom.formulation
        formulas.each_with_index do |formula, i|
          validate_formula(formula, "$.formulation[#{i}]")
        end
      end

      if md = bom.metadata
        validate_metadata(md, "$.metadata")
      end

      validate_document(bom)
      validate_spec_version_fields(bom)
    end

    # Keys whose values are `bom-ref` *references* rather than definitions.
    #
    # Restricted to the ones this object model can actually populate. Notably
    # absent are the `declarations` cross-links, whose targets (declaration
    # evidence, attestations) are not modelled yet, so every such reference would
    # look dangling.
    REF_KEYS = {
      "ref", "dependsOn", "provides",
      "assemblies", "dependencies", "vulnerabilities", "subjects",
    }

    # A reference into a *different* BOM (`urn:cdx:<serial>/<version>#<bom-ref>`)
    # rather than a local `bom-ref`. Those cannot be resolved from here.
    BOM_LINK_PREFIX = "urn:cdx:"

    # Whole-document checks that need to see every object at once, run over the
    # serialized form.
    #
    # Walking the emitted JSON rather than the object model is deliberate:
    # `bom-ref` identifiers and the references to them are spread across
    # components, services, vulnerabilities, licenses, compositions, formulation,
    # declarations and definitions, and any hand-written traversal would miss the
    # ones added later. Every `bom-ref` in the document is found by construction.
    private def validate_document(bom : BOM)
      document = JSON.parse(bom.to_json)
      defined = {} of String => String
      references = [] of {String, String}

      collect_document(document, "$", defined, references)

      references.each do |(path, ref)|
        next if defined.has_key?(ref)
        next if ref.starts_with?(BOM_LINK_PREFIX)
        add_error(path, "references unknown bom-ref '#{ref}'")
      end
    end

    private def collect_document(node : JSON::Any, path : String,
                                 defined : ::Hash(String, String),
                                 references : Array({String, String}))
      if obj = node.as_h?
        if ref = obj["bom-ref"]?.try(&.as_s?)
          if first = defined[ref]?
            add_error("#{path}.bom-ref", "duplicate bom-ref '#{ref}', already used by #{first}")
          else
            defined[ref] = path
          end
        end

        validate_license_choice(obj, path)

        obj.each do |key, value|
          child_path = "#{path}.#{key}"
          if REF_KEYS.includes?(key)
            collect_references(value, child_path, references)
            # `dependencies` is a reference list inside a composition but the
            # dependency graph itself at the document root, so keep descending.
          end
          validate_licenses_array(value, child_path) if key == "licenses"
          validate_lifecycles(value, child_path) if key == "lifecycles"
          collect_document(value, child_path, defined, references)
        end
      elsif arr = node.as_a?
        arr.each_with_index do |value, i|
          collect_document(value, "#{path}[#{i}]", defined, references)
        end
      end
    end

    private def collect_references(node : JSON::Any, path : String,
                                   references : Array({String, String}))
      if ref = node.as_s?
        references << {path, ref}
      elsif arr = node.as_a?
        arr.each_with_index do |value, i|
          value.as_s?.try { |item| references << {"#{path}[#{i}]", item} }
        end
      end
    end

    # A `licenses` entry's `license` object must carry an `id` or a `name`; the
    # schema models them as a `oneOf`, so an object with neither is invalid. This
    # used to slip through and emit `{"license":{}}`.
    private def validate_license_choice(obj : ::Hash(String, JSON::Any), path : String)
      license = obj["license"]?.try(&.as_h?)
      return unless license
      return if license.has_key?("id") || license.has_key?("name")
      add_error("#{path}.license", "must have either an 'id' or a 'name'")
    end

    # A `licenses` array is a `oneOf` in the schema: either a list of
    # `{"license": …}` entries, or a list holding a *single* `{"expression": …}`
    # (`maxItems: 1`). The XSD says the same with an `xs:choice` between
    # `<license>` elements and one `<expression>`. The object model stores both
    # kinds in one `Array(License | LicenseExpression)`, so a caller can build a
    # mixed array, or several expressions, which every official schema rejects.
    private def validate_licenses_array(node : JSON::Any, path : String)
      entries = node.as_a?
      return unless entries
      expressions = entries.count { |entry| entry.as_h?.try(&.has_key?("expression")) }
      return if expressions.zero?

      if expressions < entries.size
        add_error(path, "must not mix a license expression with named licenses; " \
                        "the schema permits either one expression or a list of licenses")
      elsif expressions > 1
        add_error(path, "must not carry more than one license expression")
      end
    end

    # A `metadata.lifecycles` entry is a `oneOf` too: either a predefined
    # `phase`, or a custom `name` (with an optional `description`) — never both.
    # The XSD models it as an `xs:choice`, and the JSON schema forbids the other
    # branch's keys outright via `additionalProperties: false`.
    private def validate_lifecycles(node : JSON::Any, path : String)
      entries = node.as_a?
      return unless entries
      entries.each_with_index do |entry, i|
        obj = entry.as_h?
        next unless obj
        next unless obj.has_key?("phase")
        next unless obj.has_key?("name") || obj.has_key?("description")
        add_error("#{path}[#{i}]", "must have either a 'phase' or a 'name', not both")
      end
    end

    # Flags anything populated on the object model that is newer than the
    # declared `specVersion` — a field that does not exist yet, an enum value
    # that is not permitted yet, or a shape the older schema cannot express.
    #
    # Anything the gate could repair becomes a warning: the emitted document is
    # schema-valid, so it would be wrong to call the BOM invalid, but the caller
    # should know data was dropped or rewritten. Only what the gate could *not*
    # repair is an error. The messages come from the gate itself, which is what
    # performed the edit.
    private def validate_spec_version_fields(bom : BOM)
      VersionGate.each_violation(bom) do |v|
        path = "#{v.path}.#{v.field}"
        if v.repaired
          @warnings << ValidationError.new(path, v.message)
        else
          add_error(path, v.message)
        end
      end
    end

    private def validate_component(comp : Component, path : String)
      add_error("#{path}.name", "must not be empty") if comp.name.empty?
      # `version` may legitimately be absent, but an explicitly empty string is
      # neither a version nor an omission.
      if (version = comp.version) && version.empty?
        add_error("#{path}.version", "must not be empty; omit it instead when unknown")
      end

      unless Component::VALID_TYPES.includes?(comp.component_type)
        add_error("#{path}.type", "invalid type '#{comp.component_type}', valid: #{Component::VALID_TYPES.join(", ")}")
      end

      if scope = comp.scope
        unless Component::VALID_SCOPES.includes?(scope)
          add_error("#{path}.scope", "invalid scope '#{scope}'")
        end
      end

      if cpe = comp.cpe
        unless cpe.matches?(CPE_PATTERN)
          add_error("#{path}.cpe", "'#{cpe}' is not a well-formed CPE")
        end
      end

      if data = comp.data
        data.each_with_index do |entry, i|
          validate_component_data(entry, "#{path}.data[#{i}]")
        end
      end

      if hashes = comp.hashes
        hashes.each_with_index do |hash, i|
          validate_hash(hash, "#{path}.hashes[#{i}]")
        end
      end

      if ext_refs = comp.external_references
        ext_refs.each_with_index do |ref, i|
          validate_external_reference(ref, "#{path}.externalReferences[#{i}]")
        end
      end

      if evidence = comp.evidence
        validate_evidence(evidence, "#{path}.evidence")
      end

      if sub = comp.components
        sub.each_with_index do |c, i|
          validate_component(c, "#{path}.components[#{i}]")
        end
      end
    end

    # `evidence.identity` carries two enums the object model types as plain
    # strings: `field` (`identityFieldType`) and each method's `technique`
    # (`evidenceTechnique`).
    private def validate_evidence(evidence : Evidence, path : String)
      identities = evidence.identity
      return unless identities

      identities.each_with_index do |identity, i|
        identity_path = "#{path}.identity[#{i}]"
        if field = identity.field
          unless EvidenceIdentity::VALID_FIELDS.includes?(field)
            add_error("#{identity_path}.field",
              "invalid identity field '#{field}', valid: #{EvidenceIdentity::VALID_FIELDS.join(", ")}")
          end
        end

        next unless methods = identity.methods
        methods.each_with_index do |method, j|
          unless EvidenceMethod::VALID_TECHNIQUES.includes?(method.technique)
            add_error("#{identity_path}.methods[#{j}].technique",
              "invalid technique '#{method.technique}', valid: #{EvidenceMethod::VALID_TECHNIQUES.join(", ")}")
          end
        end
      end
    end

    # A CPE 2.2 URI (`cpe:/part:vendor:…`) or a CPE 2.3 formatted string
    # (`cpe:2.3:` plus eleven colon-separated components).
    #
    # A shape check, not the XSD's full pattern: it exists to reject a value that
    # is plainly not a CPE, which is the mistake that actually happens. Fields
    # containing escaped colons (`\:`) are rare and not accounted for.
    CPE_PATTERN = /\A(cpe:\/[aho]?(:[^:]*){0,6}|cpe:2\.3(:[^:]*){11})\z/i

    private def validate_component_data(data : ComponentData, path : String)
      if data_type = data.data_type
        unless ComponentData::VALID_DATA_TYPES.includes?(data_type)
          add_error("#{path}.type", "invalid data type '#{data_type}', valid: #{ComponentData::VALID_DATA_TYPES.join(", ")}")
        end
      end
    end

    private def validate_hash(hash : Hash, path : String)
      unless Hash::VALID_ALGORITHMS.includes?(hash.algorithm)
        add_error("#{path}.alg", "invalid hash algorithm '#{hash.algorithm}', valid: #{Hash::VALID_ALGORITHMS.join(", ")}")
      end
    end

    private def validate_external_reference(ref : ExternalReference, path : String)
      unless ExternalReference::VALID_TYPES.includes?(ref.ref_type)
        add_error("#{path}.type", "invalid external reference type '#{ref.ref_type}', valid: #{ExternalReference::VALID_TYPES.join(", ")}")
      end

      if hashes = ref.hashes
        hashes.each_with_index do |hash, i|
          validate_hash(hash, "#{path}.hashes[#{i}]")
        end
      end
    end

    private def validate_service(svc : Service, path : String)
      add_error("#{path}.name", "must not be empty") if svc.name.empty?

      if sub = svc.services
        sub.each_with_index do |s, i|
          validate_service(s, "#{path}.services[#{i}]")
        end
      end
    end

    private def validate_formula(formula : Formula, path : String)
      if workflows = formula.workflows
        workflows.each_with_index do |wf, i|
          validate_workflow(wf, "#{path}.workflows[#{i}]")
        end
      end
    end

    private def validate_workflow(wf : Workflow, path : String)
      if tasks = wf.tasks
        tasks.each_with_index do |task, i|
          validate_task(task, "#{path}.tasks[#{i}]")
        end
      end
    end

    private def validate_task(task : Task, path : String)
      if types = task.task_types
        types.each_with_index do |t, i|
          unless Task::VALID_TASK_TYPES.includes?(t)
            add_error("#{path}.taskTypes[#{i}]", "invalid task type '#{t}', valid: #{Task::VALID_TASK_TYPES.join(", ")}")
          end
        end
      end
    end

    private def validate_vulnerability(vuln : Vulnerability, path : String)
      if analysis = vuln.analysis
        if state = analysis.state
          unless VulnerabilityAnalysis::VALID_STATES.includes?(state)
            add_error("#{path}.analysis.state", "invalid state '#{state}'")
          end
        end
        if justification = analysis.justification
          unless VulnerabilityAnalysis::VALID_JUSTIFICATIONS.includes?(justification)
            add_error("#{path}.analysis.justification", "invalid justification '#{justification}'")
          end
        end
      end

      if ratings = vuln.ratings
        ratings.each_with_index do |rating, i|
          if score = rating.score
            unless score >= 0.0 && score <= 10.0
              add_error("#{path}.ratings[#{i}].score", "must be between 0.0 and 10.0")
            end
          end
          if severity = rating.severity
            unless VulnerabilityRating::VALID_SEVERITIES.includes?(severity)
              add_error("#{path}.ratings[#{i}].severity", "invalid severity '#{severity}'")
            end
          end
          if scoring_method = rating.method
            unless VulnerabilityRating::VALID_METHODS.includes?(scoring_method)
              add_error("#{path}.ratings[#{i}].method", "invalid scoring method '#{scoring_method}'")
            end
          end
        end
      end

      if affects = vuln.affects
        affects.each_with_index do |affect, i|
          if versions = affect.versions
            versions.each_with_index do |ver, j|
              if status = ver.status
                unless AffectedVersion::VALID_STATUSES.includes?(status)
                  add_error("#{path}.affects[#{i}].versions[#{j}].status", "invalid status '#{status}'")
                end
              end
            end
          end
        end
      end
    end

    private def validate_composition(comp : Composition, path : String)
      unless Composition::VALID_AGGREGATES.includes?(comp.aggregate)
        add_error("#{path}.aggregate", "invalid aggregate '#{comp.aggregate}'")
      end
    end

    private def validate_metadata(metadata : Metadata, path : String)
      if timestamp = metadata.timestamp
        unless valid_timestamp?(timestamp)
          add_error("#{path}.timestamp", "'#{timestamp}' is not an RFC 3339 date-time")
        end
      end

      if lifecycles = metadata.lifecycles
        lifecycles.each_with_index do |lc, i|
          if phase = lc.phase
            unless Lifecycle::VALID_PHASES.includes?(phase)
              add_error("#{path}.lifecycles[#{i}].phase", "invalid phase '#{phase}'")
            end
          end
        end
      end

      # The root component lives in `metadata.component` and is subject to the
      # same structural rules (name/version/type/scope/hashes/externalReferences)
      # as the entries of `bom.components`; validate it the same way so an
      # invalid root is not silently accepted while the schema rejects it.
      if comp = metadata.component
        validate_component(comp, "#{path}.component")
      end
    end

    # Both schema families type timestamps as a date-time (`xs:dateTime` /
    # `format: date-time`), so a free-form string is a validation failure
    # downstream rather than here.
    private def valid_timestamp?(timestamp : String) : Bool
      Time.parse_rfc3339(timestamp)
      true
    rescue Time::Format::Error
      false
    end

    private def add_error(path : String, message : String)
      @errors << ValidationError.new(path, message)
    end
  end
end
