require "json"
require "xml"

module CycloneDX
  # Spec-version field and enum gating.
  #
  # CycloneDX grew over successive spec versions in two different ways, and both
  # have to be gated:
  #
  #   * **fields** were added — a BOM declared as `specVersion` 1.4 must NEVER
  #     contain a field that only exists from 1.5 on;
  #   * **enum values** were added — `component/@type` went from 8 permitted
  #     values in 1.4 to 13 in 1.6, and `externalReference/@type` from 16 to 47.
  #     A structurally-correct document whose `type` is `cryptographic-asset`
  #     still fails 1.4 validation.
  #
  # `VersionGate` is the single source of truth for "what was introduced when".
  # It drives:
  #   * a post-serialization JSON filter (`filter_json_any`),
  #   * an equivalent XML filter (`filter_xml`),
  #   * the `Validator`, which reports whatever the filter had to change.
  #
  # The last point matters: `violations` does not re-implement the rules, it
  # *runs* the JSON filter and collects what it did. The validator therefore
  # cannot fall out of sync with the serializers.
  #
  # ### What the gate does about an out-of-range value
  #
  # Too-new fields are stripped. Too-new enum values are downgraded to the
  # enum's designated catch-all where the spec defines one (`other` for
  # `externalReferenceType`, `not_specified` for `aggregateType`). Where there is
  # no catch-all the value is left alone, because inventing a substitute would
  # misrepresent the component — `Validator` reports it instead, and the CLI
  # validates before writing so it can never emit such a document. The one
  # exception is `hash/@alg`, which is required and has no catch-all: there the
  # whole hash entry is dropped, since an optional hash is better lost than
  # invalid.
  #
  # The field map is keyed by *context* (the kind of object a field lives in)
  # rather than by bare field name, because some names are ambiguous (e.g. `tags`
  # exists on `component` only from 1.6 but on `releaseNotes` since 1.4, and
  # `bom-ref` is core on a component but 1.5-only on a license).
  module VersionGate
    # Ordering of the supported spec versions, oldest first.
    VERSION_ORDER = {"1.4" => 0, "1.5" => 1, "1.6" => 2, "1.7" => 3}

    # Returns true when `field_version` is newer than the declared
    # `spec_version` (i.e. the field must be stripped / flagged).
    def self.newer?(field_version : String, spec_version : String) : Bool
      fv = VERSION_ORDER[field_version]?
      sv = VERSION_ORDER[spec_version]?
      return false if fv.nil? || sv.nil?
      fv > sv
    end

    # ---- field tables ----------------------------------------------------

    # Context => { json_key => minimum_spec_version }.
    #
    # The contexts identify *which kind of object* the gated keys live in; see
    # `CHILD_CONTEXT` for how the JSON filter descends into them and
    # `XML_CONTEXT` for the XML equivalent.
    #
    # Only fields the object model can actually produce are listed. 1.7 added
    # `bom.citations`, `metadata.distributionConstraints`,
    # `component.isExternal/patentAssertions/versionRange`,
    # `service.patentAssertions` and `externalReference.properties`; none are
    # modelled yet, so none appear here.
    GATED = {
      bom: {
        # 1.5+
        "annotations" => "1.5",
        "formulation" => "1.5",
        # 1.6+
        "definitions"  => "1.6",
        "declarations" => "1.6",
      },
      metadata: {
        # 1.5+
        "lifecycles" => "1.5",
        # 1.6+
        "manufacturer" => "1.6",
      },
      component: {
        # 1.5+
        "modelCard" => "1.5",
        "data"      => "1.5",
        # 1.6+
        "tags"             => "1.6",
        "omniborId"        => "1.6",
        "swhid"            => "1.6",
        "cryptoProperties" => "1.6",
        "manufacturer"     => "1.6",
        # The `authors` ARRAY is 1.6+; the single `author` string is older and
        # is intentionally NOT gated.
        "authors" => "1.6",
      },
      license: {
        # 1.5+ (license `bom-ref` was introduced in 1.5)
        "bom-ref" => "1.5",
        # 1.6+
        "acknowledgement" => "1.6",
      },
      # A `LicenseExpression` sits directly in a licenses array (no `license`
      # wrapper key), so its `bom-ref`/`acknowledgement` keys are gated at the
      # array-entry level. The `{ "license": {...} }` wrapper carries only the
      # `license` key here, so it is unaffected.
      licenses_array: {
        # 1.5+
        "bom-ref" => "1.5",
        # 1.6+
        "acknowledgement" => "1.6",
      },
      service: {
        # 1.5+
        "trustZone" => "1.5",
        # 1.6+
        "tags" => "1.6",
      },
      composition: {
        # 1.5+ (`bom-ref` is an attribute in XML — see XML_GATED_ATTRS)
        "bom-ref"         => "1.5",
        "vulnerabilities" => "1.5",
      },
      vulnerability: {
        # 1.5+
        "workaround"     => "1.5",
        "proofOfConcept" => "1.5",
        "rejected"       => "1.5",
      },
      vulnerability_analysis: {
        # 1.5+
        "firstIssued" => "1.5",
        "lastUpdated" => "1.5",
      },
      evidence: {
        # 1.5+ (1.4 evidence carries only `licenses` and `copyright`)
        "identity"    => "1.5",
        "occurrences" => "1.5",
        "callstack"   => "1.5",
      },
      dependency: {
        # 1.6+
        "provides" => "1.6",
      },
      # `tools` is a flat list of `toolType` in 1.4 and gained the
      # components/services object form in 1.5. There is no spec-defined way to
      # express the object form in 1.4, so it is dropped rather than guessed at;
      # callers targeting 1.4 should populate the legacy `tools:` list, which is
      # valid at every version and is what the CLI emits.
      tools: {
        # 1.5+
        "components" => "1.5",
        "services"   => "1.5",
      },
    }

    # Fields the JSON schema gained later than the XSD did, so they must be
    # stripped from JSON but kept in XML. `bom.properties` is the only one: the
    # 1.4 XSD lists `properties` among the `bom` element's children, but the 1.4
    # JSON schema does not allow it at the document root.
    GATED_JSON_ONLY = {
      bom: {
        "properties" => "1.5",
      },
    }

    # ---- enum tables -----------------------------------------------------
    #
    # Value => the oldest spec version that permits it. Values permitted since
    # 1.4 are omitted. Derived from the vendored XSD enumerations; a spec
    # cross-checks these tables against the schemas so they cannot drift.

    # `classification` (component/@type).
    COMPONENT_TYPE_VERSIONS = {
      "platform"               => "1.5",
      "device-driver"          => "1.5",
      "machine-learning-model" => "1.5",
      "data"                   => "1.5",
      "cryptographic-asset"    => "1.6",
    }

    # `externalReferenceType` (externalReference/@type).
    EXTERNAL_REFERENCE_TYPE_VERSIONS = {
      "distribution-intake"       => "1.5",
      "security-contact"          => "1.5",
      "model-card"                => "1.5",
      "log"                       => "1.5",
      "configuration"             => "1.5",
      "evidence"                  => "1.5",
      "formulation"               => "1.5",
      "attestation"               => "1.5",
      "threat-model"              => "1.5",
      "adversary-model"           => "1.5",
      "risk-assessment"           => "1.5",
      "vulnerability-assertion"   => "1.5",
      "exploitability-statement"  => "1.5",
      "pentest-report"            => "1.5",
      "static-analysis-report"    => "1.5",
      "dynamic-analysis-report"   => "1.5",
      "runtime-analysis-report"   => "1.5",
      "component-analysis-report" => "1.5",
      "maturity-report"           => "1.5",
      "certification-report"      => "1.5",
      "quality-metrics"           => "1.5",
      "codified-infrastructure"   => "1.5",
      "poam"                      => "1.5",
      "source-distribution"       => "1.6",
      "electronic-signature"      => "1.6",
      "digital-signature"         => "1.6",
      "rfc-9116"                  => "1.6",
      "patent"                    => "1.7",
      "patent-family"             => "1.7",
      "patent-assertion"          => "1.7",
      "citation"                  => "1.7",
    }

    # `aggregateType` (composition/aggregate).
    AGGREGATE_VERSIONS = {
      "incomplete_first_party_proprietary_only" => "1.5",
      "incomplete_first_party_opensource_only"  => "1.5",
      "incomplete_third_party_proprietary_only" => "1.5",
      "incomplete_third_party_opensource_only"  => "1.5",
    }

    # `hashAlg` (hash/@alg).
    HASH_ALG_VERSIONS = {
      "Streebog-256" => "1.7",
      "Streebog-512" => "1.7",
    }

    # Context => { json_key => value-version table }.
    GATED_ENUMS = {
      component:          {"type" => COMPONENT_TYPE_VERSIONS},
      external_reference: {"type" => EXTERNAL_REFERENCE_TYPE_VERSIONS},
      composition:        {"aggregate" => AGGREGATE_VERSIONS},
      hash:               {"alg" => HASH_ALG_VERSIONS},
    }

    # The catch-all each enum designates for "a type this document cannot
    # express". Enums with no catch-all are absent, which is what makes a value
    # non-downgradeable.
    ENUM_FALLBACK = {
      external_reference: {"type" => "other"},
      composition:        {"aggregate" => "not_specified"},
    }

    # ---- JSON filtering --------------------------------------------------

    # {parent context, json key} => the context to filter the value under.
    #
    # `externalReferences` and `hashes` are matched by key alone (see
    # `child_context`) because they hang off many different parents and the key
    # name is unambiguous across the whole schema.
    CHILD_CONTEXT = {
      {:bom, "metadata"}        => :metadata,
      {:bom, "components"}      => :component,
      {:bom, "services"}        => :service,
      {:bom, "compositions"}    => :composition,
      {:bom, "vulnerabilities"} => :vulnerability,
      {:bom, "dependencies"}    => :dependency,

      {:metadata, "component"} => :component,
      {:metadata, "licenses"}  => :licenses_array,
      {:metadata, "tools"}     => :tools,

      # The 1.5+ object form of `metadata.tools` holds full components/services.
      {:tools, "components"} => :component,
      {:tools, "services"}   => :service,

      {:component, "components"} => :component,
      {:component, "licenses"}   => :licenses_array,
      {:component, "pedigree"}   => :pedigree,
      {:component, "evidence"}   => :evidence,

      # Pedigree ancestry entries are themselves components.
      {:pedigree, "ancestors"}   => :component,
      {:pedigree, "descendants"} => :component,
      {:pedigree, "variants"}    => :component,

      {:evidence, "licenses"} => :licenses_array,

      {:service, "services"} => :service,
      {:service, "licenses"} => :licenses_array,

      {:vulnerability, "analysis"} => :vulnerability_analysis,

      {:licenses_array, "license"} => :license,
    }

    # A single spec-version violation: the JSON path of the owning object, the
    # offending field, the minimum spec version it requires, and a description
    # of what the gate did about it.
    #
    # `repaired` says whether the gate could make the document valid anyway.
    # Almost everything is repairable — a too-new field is stripped, a too-new
    # enum value is swapped for its catch-all — and those are a lossy downgrade,
    # not an invalid document. The exception is an enum with no catch-all
    # (`component/@type`), where the value has to stay and the output really is
    # invalid. `Validator` reports the two differently for that reason.
    record Violation,
      path : String,
      field : String,
      min_version : String,
      message : String,
      repaired : Bool = true

    # Returns a copy of `json` (a serialized CycloneDX BOM document) filtered
    # down to what `spec_version` permits. When `violations` is given, every
    # edit the filter makes is appended to it.
    def self.filter_json_any(json : String, spec_version : String,
                             violations : Array(Violation)? = nil) : JSON::Any
      filtered = filter_node(JSON.parse(json), spec_version, :bom, "$", violations)
      filtered || JSON::Any.new(nil)
    end

    # String-in/string-out convenience wrapper around `filter_json_any`.
    def self.filter_json(json : String, spec_version : String) : String
      filter_json_any(json, spec_version).to_json
    end

    # Recursively filters a `JSON::Any` node. `context` is the kind of object we
    # are currently inside (see `GATED`); `path` is its JSON path, used only for
    # violation reporting. Returns nil when the node itself cannot be
    # represented in `spec_version` and must be dropped from its parent array.
    private def self.filter_node(node : JSON::Any, spec_version : String, context : Symbol,
                                 path : String, violations : Array(Violation)?) : JSON::Any?
      if obj = node.as_h?
        return if drop_object?(obj, spec_version, context, path, violations)
        filter_object(obj, spec_version, context, path, violations)
      elsif arr = node.as_a?
        # Array entries stay in the parent's context: `components: [...]` is a
        # list of components, `hashes: [...]` a list of hashes.
        filtered = [] of JSON::Any
        arr.each_with_index do |value, i|
          child = filter_node(value, spec_version, context, "#{path}[#{i}]", violations)
          filtered << child if child
        end
        JSON::Any.new(filtered)
      else
        node
      end
    end

    private def self.filter_object(obj : ::Hash(String, JSON::Any), spec_version : String,
                                   context : Symbol, path : String,
                                   violations : Array(Violation)?) : JSON::Any
      gated = GATED[context]?
      json_only = GATED_JSON_ONLY[context]?
      filtered = {} of String => JSON::Any

      obj.each do |key, value|
        if min = gated.try(&.[key]?) || json_only.try(&.[key]?)
          if newer?(min, spec_version)
            violations.try(&.<< Violation.new(path, key, min,
              "field '#{key}' requires specVersion >= #{min}, but BOM declares #{spec_version}"))
            next
          end
        end

        if downgraded = downgrade_enum(context, key, value, spec_version, path, violations)
          filtered[key] = downgraded
          next
        end

        child = filter_node(value, spec_version, child_context(context, key),
          "#{path}.#{key}", violations)
        next unless child
        child = collapse_evidence_identity(context, key, child, spec_version, path, violations)
        next unless child
        # A container the filter emptied out is dropped rather than emitted as
        # `[]`, which would assert "none exist" instead of "none can be expressed
        # at this version". Containers that were already empty are preserved.
        next if emptied_by_filter?(value, child)
        filtered[key] = child
      end

      JSON::Any.new(filtered)
    end

    # True when `filtered` is empty only because the filter removed everything
    # the non-empty `original` held. Containers that were already empty are not
    # the gate's doing and are left alone.
    private def self.emptied_by_filter?(original : JSON::Any, filtered : JSON::Any) : Bool
      if (before = original.as_a?) && (after = filtered.as_a?)
        return after.empty? && !before.empty?
      end
      if (before = original.as_h?) && (after = filtered.as_h?)
        return after.empty? && !before.empty?
      end
      false
    end

    # Determines the context to filter `key`'s value under.
    private def self.child_context(context : Symbol, key : String) : Symbol
      case key
      when "externalReferences" then :external_reference
      when "hashes"             then :hash
      else                           CHILD_CONTEXT[{context, key}]? || :none
      end
    end

    # True when the object as a whole has to go. Only a `hash` qualifies: `alg`
    # is required and `hashAlg` defines no catch-all, so an unrepresentable
    # algorithm leaves nothing valid to emit. A `component` whose `type` is too
    # new is in the same position but is never droppable, so that is reported by
    # `Validator` and left in place (see the class docs).
    private def self.drop_object?(obj : ::Hash(String, JSON::Any), spec_version : String,
                                  context : Symbol, path : String,
                                  violations : Array(Violation)?) : Bool
      return false unless context == :hash
      alg = obj["alg"]?.try(&.as_s?)
      return false unless alg
      min = HASH_ALG_VERSIONS[alg]?
      return false unless min && newer?(min, spec_version)
      violations.try(&.<< Violation.new(path, "alg", min,
        "hash algorithm '#{alg}' requires specVersion >= #{min}, but BOM declares " \
        "#{spec_version}; the hash was dropped"))
      true
    end

    # Rewrites an enum value that `spec_version` does not permit to the enum's
    # catch-all. Returns nil when `key` is not a gated enum, when the value is
    # in range, or when the enum has no catch-all — in the last case the value
    # is left untouched and reported.
    private def self.downgrade_enum(context : Symbol, key : String, value : JSON::Any,
                                    spec_version : String, path : String,
                                    violations : Array(Violation)?) : JSON::Any?
      table = GATED_ENUMS[context]?.try(&.[key]?)
      return unless table
      current = value.as_s?
      return unless current
      min = table[current]?
      return unless min && newer?(min, spec_version)

      fallback = ENUM_FALLBACK[context]?.try(&.[key]?)
      if fallback
        violations.try(&.<< Violation.new(path, key, min,
          "'#{key}' value '#{current}' requires specVersion >= #{min}, but BOM declares " \
          "#{spec_version}; emitted as '#{fallback}'"))
        JSON::Any.new(fallback)
      else
        violations.try(&.<< Violation.new(path, key, min,
          "'#{key}' value '#{current}' requires specVersion >= #{min}, but BOM declares " \
          "#{spec_version} and the enum has no older equivalent",
          repaired: false))
        nil
      end
    end

    # `evidence.identity` is a single object in 1.5 and object-or-array from 1.6
    # on, while the model always emits an array. Collapse it for 1.5; a second
    # identity cannot be expressed there at all, so only the first survives.
    private def self.collapse_evidence_identity(context : Symbol, key : String, node : JSON::Any,
                                                spec_version : String, path : String,
                                                violations : Array(Violation)?) : JSON::Any?
      return node unless context == :evidence && key == "identity"
      return node unless spec_version == "1.5"
      arr = node.as_a?
      return node unless arr
      if arr.size > 1
        violations.try(&.<< Violation.new(path, key, "1.6",
          "more than one evidence identity requires specVersion >= 1.6, but BOM declares " \
          "#{spec_version}; only the first was kept"))
      end
      arr.first?
    end

    # ---- XML filtering ---------------------------------------------------

    # The XML filter reuses `GATED`: every gated JSON key maps to an XML element
    # of the same name, and the gating context is identified by the *parent*
    # element's name. `GATED_JSON_ONLY` is deliberately not consulted here.
    XML_CONTEXT = {
      "bom"           => :bom,
      "metadata"      => :metadata,
      "component"     => :component,
      "service"       => :service,
      "composition"   => :composition,
      "vulnerability" => :vulnerability,
      "analysis"      => :vulnerability_analysis,
      "evidence"      => :evidence,
      "dependency"    => :dependency,
      "tools"         => :tools,
    }

    # Fields that are attributes in XML rather than elements, by element name.
    XML_GATED_ATTRS = {
      "license"     => {"bom-ref" => "1.5", "acknowledgement" => "1.6"},
      "expression"  => {"bom-ref" => "1.5", "acknowledgement" => "1.6"},
      "composition" => {"bom-ref" => "1.5"},
    }

    # Enum-valued attributes, by element name.
    XML_ENUM_ATTRS = {
      "component" => {"type" => COMPONENT_TYPE_VERSIONS},
      "reference" => {"type" => EXTERNAL_REFERENCE_TYPE_VERSIONS},
      "hash"      => {"alg" => HASH_ALG_VERSIONS},
    }

    # Catch-alls for `XML_ENUM_ATTRS`, mirroring `ENUM_FALLBACK`.
    XML_ENUM_ATTR_FALLBACK = {
      "reference" => {"type" => "other"},
    }

    # Elements whose *text content* is an enum value, with their catch-all.
    XML_ENUM_TEXT = {
      "aggregate" => AGGREGATE_VERSIONS,
    }
    XML_ENUM_TEXT_FALLBACK = {
      "aggregate" => "not_specified",
    }

    # Returns a copy of `xml` with elements, attributes and enum values newer
    # than `spec_version` removed or downgraded.
    def self.filter_xml(xml : String, spec_version : String) : String
      doc = XML.parse(xml)
      if root = doc.root
        strip_xml(root, spec_version)
      end
      # Re-serialise. `to_xml` on the document includes the XML declaration to
      # match the original `XML.build` output shape.
      doc.to_xml(options: XML::SaveOptions::AS_XML)
    end

    private def self.strip_xml(node : XML::Node, spec_version : String) : Nil
      collapse_xml_identity(node, spec_version)

      context = XML_CONTEXT[node.name]?
      gated = context ? GATED[context]? : nil

      # Collect children first; mutating the tree while iterating is unsafe.
      children = node.children.select(&.element?).to_a

      children.each do |child|
        if gated && (min = gated[child.name]?) && newer?(min, spec_version)
          child.unlink
          next
        end

        if droppable_xml_hash?(child, spec_version)
          child.unlink
          next
        end

        strip_xml_attrs(child, spec_version)
        downgrade_xml_enums(child, spec_version)

        had_children = child.children.any?(&.element?)
        strip_xml(child, spec_version)
        # Mirrors `emptied_by_filter?`: a container the filter hollowed out is
        # removed rather than left as an empty element.
        child.unlink if had_children && child.children.none?(&.element?)
      end
    end

    # Mirrors `collapse_evidence_identity` for XML: `<identity>` is maxOccurs=1
    # in the 1.5 XSD and unbounded from 1.6 on.
    private def self.collapse_xml_identity(node : XML::Node, spec_version : String) : Nil
      return unless node.name == "evidence" && spec_version == "1.5"
      kept = false
      node.children.select(&.element?).each do |child|
        next unless child.name == "identity"
        kept ? child.unlink : (kept = true)
      end
    end

    # Mirrors `drop_object?`.
    private def self.droppable_xml_hash?(node : XML::Node, spec_version : String) : Bool
      return false unless node.name == "hash"
      alg = node["alg"]?
      return false unless alg
      min = HASH_ALG_VERSIONS[alg]?
      !!(min && newer?(min, spec_version))
    end

    private def self.strip_xml_attrs(node : XML::Node, spec_version : String) : Nil
      table = XML_GATED_ATTRS[node.name]?
      return unless table
      table.each do |attr, min|
        node.delete(attr) if newer?(min, spec_version) && node[attr]?
      end
    end

    private def self.downgrade_xml_enums(node : XML::Node, spec_version : String) : Nil
      if table = XML_ENUM_ATTRS[node.name]?
        table.each do |attr, versions|
          value = node[attr]?
          next unless value
          min = versions[value]?
          next unless min && newer?(min, spec_version)
          if fallback = XML_ENUM_ATTR_FALLBACK[node.name]?.try(&.[attr]?)
            node[attr] = fallback
          end
        end
      end

      if versions = XML_ENUM_TEXT[node.name]?
        value = node.content
        if (min = versions[value]?) && newer?(min, spec_version)
          if fallback = XML_ENUM_TEXT_FALLBACK[node.name]?
            node.content = fallback
          end
        end
      end
    end

    # ---- Validation ------------------------------------------------------

    # Yields a `Violation` for everything the gate has to strip, drop or rewrite
    # to make `bom` valid at its declared `specVersion`. Used by `Validator`.
    def self.each_violation(bom, & : Violation ->) : Nil
      violations(bom).each { |v| yield v }
    end

    # Collects all spec-version violations on `bom`.
    #
    # This *runs the JSON filter* over the pre-gate document and reports what it
    # changed, rather than re-deriving the rules. Anything the filter learns to
    # handle is therefore reported automatically, and the two can never disagree.
    def self.violations(bom) : Array(Violation)
      found = [] of Violation
      filter_json_any(bom.raw_json, bom.spec_version, found)
      found
    end
  end
end
