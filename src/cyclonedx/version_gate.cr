require "json"
require "xml"

module CycloneDX
  # Spec-version field gating.
  #
  # CycloneDX added fields over successive spec versions. A BOM declared as
  # `specVersion` 1.4 must NEVER contain fields that were only introduced in
  # 1.5 or 1.6, otherwise it fails schema validation. The same applies to a
  # 1.5 BOM with respect to 1.6-only fields.
  #
  # `VersionGate` is the single source of truth for "which field was added in
  # which version". It drives:
  #   * a post-serialization JSON filter (`filter_json`),
  #   * an equivalent XML filter (`filter_xml`),
  #   * the `Validator` (so direct object-model users get told when they
  #     populated a field newer than the declared `specVersion`).
  #
  # The map is keyed by *context* (the kind of object a field lives in) rather
  # than by bare field name, because some names are ambiguous (e.g. `tags`
  # exists on `component` only from 1.6 but on `releaseNotes` since 1.4, and
  # `bom-ref` is core on a component but 1.6-only on a license).
  module VersionGate
    # Ordering of the supported spec versions, oldest first.
    VERSION_ORDER = {"1.4" => 0, "1.5" => 1, "1.6" => 2}

    # Returns true when `field_version` is newer than the declared
    # `spec_version` (i.e. the field must be stripped / flagged).
    def self.newer?(field_version : String, spec_version : String) : Bool
      fv = VERSION_ORDER[field_version]?
      sv = VERSION_ORDER[spec_version]?
      return false if fv.nil? || sv.nil?
      fv > sv
    end

    # Context => { json_key => minimum_spec_version }.
    #
    # The contexts identify *which kind of object* the gated keys live in:
    #   :bom       — the top-level BOM object.
    #   :metadata  — a `metadata` object.
    #   :component — any `component` object (top-level or nested).
    #   :license   — a license object (the value under a `license` wrapper key).
    #
    # XML uses the same element names as the JSON keys for all gated fields,
    # so the XML filter reuses this same map.
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
        # 1.6+ (the model only carries the deprecated `manufacture` field,
        # which is valid in 1.4; the new `manufacturer` is listed here so the
        # gate stays correct if it is ever added to the model).
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
        # 1.6+
        "bom-ref"         => "1.6",
        "acknowledgement" => "1.6",
      },
      # A `LicenseExpression` sits directly in a licenses array (no `license`
      # wrapper key), so its 1.6+ `bom-ref`/`acknowledgement` keys are gated at
      # the array-entry level. The `{ "license": {...} }` wrapper carries only
      # the `license` key here, so it is unaffected.
      licenses_array: {
        # 1.6+
        "bom-ref"         => "1.6",
        "acknowledgement" => "1.6",
      },
    }

    # ---- JSON filtering --------------------------------------------------

    # Returns a copy of `json` (a serialized CycloneDX BOM document) with every
    # key newer than `spec_version` removed.
    def self.filter_json(json : String, spec_version : String) : String
      any = JSON.parse(json)
      filtered = filter_node(any, spec_version, :bom)
      filtered.to_json
    end

    # Recursively filters a `JSON::Any` node. `context` is the kind of object
    # we are currently inside (see `GATED`).
    private def self.filter_node(node : JSON::Any, spec_version : String, context : Symbol) : JSON::Any
      if obj = node.as_h?
        filtered = {} of String => JSON::Any
        gated = GATED[context]?
        obj.each do |key, value|
          if gated && (min = gated[key]?) && newer?(min, spec_version)
            next # strip newer-than-declared field
          end
          filtered[key] = filter_child(key, value, spec_version, context)
        end
        JSON::Any.new(filtered)
      elsif arr = node.as_a?
        JSON::Any.new(arr.map { |v| filter_node(v, spec_version, context).as(JSON::Any) })
      else
        node
      end
    end

    # Determines the child context when descending into `key` and recurses.
    private def self.filter_child(key : String, value : JSON::Any, spec_version : String, context : Symbol) : JSON::Any
      child_context =
        case {context, key}
        when {:bom, "metadata"}           then :metadata
        when {:bom, "components"}         then :component
        when {:metadata, "component"}     then :component
        when {:component, "components"}   then :component
        when {:component, "licenses"}     then :licenses_array
        when {:metadata, "licenses"}      then :licenses_array
        when {:licenses_array, "license"} then :license
        else
          # Stay in the current context for arrays that hold the same kind of
          # object; otherwise enter a neutral context with no gated keys.
          neutral_child(context, key)
        end
      filter_node(value, spec_version, child_context)
    end

    # Contexts whose nested objects carry the same gated keys (e.g. an array of
    # components stays in :component) vs. anything else which becomes neutral.
    private def self.neutral_child(context : Symbol, key : String) : Symbol
      case context
      when :component
        # `components` already handled above; everything else under a component
        # (hashes, externalReferences, ...) has no gated keys.
        :none
      when :licenses_array
        # An entry of a licenses array is either a `{ "license": {...} }`
        # wrapper or an expression object; descend keeping the array context so
        # the `license` key is recognised.
        :licenses_array
      else
        :none
      end
    end

    # ---- XML filtering ---------------------------------------------------

    # The XML filter reuses `GATED`: each gated JSON key maps to an XML element
    # of the same name. Elements are stripped by matching the gated key against
    # the element's parent (e.g. a `tags` element is only gated when its parent
    # is a `component`). License-level gating is on attributes, not elements,
    # and is handled via `XML_LICENSE_ATTRS`.

    # License-level attributes that are 1.6+ only.
    XML_LICENSE_ATTRS = {"bom-ref" => "1.6", "acknowledgement" => "1.6"}

    # Returns a copy of `xml` with elements/attributes newer than
    # `spec_version` removed.
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
      # Collect children first; mutating the tree while iterating is unsafe.
      children = node.children.select(&.element?).to_a

      children.each do |child|
        name = child.name

        if gated_component_field?(name, spec_version, child)
          child.unlink
          next
        end

        if gated_simple_field?(name, spec_version, child)
          child.unlink
          next
        end

        # License-level 1.6 attributes. These live on both the `<license>`
        # wrapper element and a bare `<expression>` element (a LicenseExpression).
        if name == "license" || name == "expression"
          XML_LICENSE_ATTRS.each do |attr, min|
            if newer?(min, spec_version) && child[attr]?
              child.delete(attr)
            end
          end
        end

        strip_xml(child, spec_version)
      end
    end

    # Component-context gated elements (modelCard/data/tags/.../authors). These
    # are only stripped when their parent element is a `component`.
    private def self.gated_component_field?(name : String, spec_version : String, node : XML::Node) : Bool
      min = GATED[:component][name]?
      return false unless min
      parent = node.parent
      return false unless parent && parent.element? && parent.name == "component"
      newer?(min, spec_version)
    end

    # Non-component gated elements anchored by parent element name.
    private def self.gated_simple_field?(name : String, spec_version : String, node : XML::Node) : Bool
      parent = node.parent
      return false unless parent && parent.element?
      pname = parent.name

      min =
        case {pname, name}
        when {"bom", "annotations"}, {"bom", "formulation"},
             {"bom", "definitions"}, {"bom", "declarations"}
          GATED[:bom][name]?
        when {"metadata", "lifecycles"}, {"metadata", "manufacturer"}
          GATED[:metadata][name]?
        end

      return false unless min
      newer?(min, spec_version)
    end

    # ---- Validation ------------------------------------------------------

    # A single field-gating violation: the JSON path of the owning object, the
    # offending field name, and the minimum spec version that field requires.
    record Violation, path : String, field : String, min_version : String

    # Yields a `Violation` for every populated field on `bom` that is newer
    # than `bom.spec_version`. Used by `Validator`.
    def self.each_violation(bom, & : Violation ->) : Nil
      violations(bom).each { |v| yield v }
    end

    # Collects all field-gating violations on `bom`.
    def self.violations(bom) : Array(Violation)
      sv = bom.spec_version
      result = [] of Violation

      # bom-level
      result << Violation.new("$", "annotations", "1.5") if !bom.annotations.nil? && newer?("1.5", sv)
      result << Violation.new("$", "formulation", "1.5") if !bom.formulation.nil? && newer?("1.5", sv)
      result << Violation.new("$", "definitions", "1.6") if !bom.definitions.nil? && newer?("1.6", sv)
      result << Violation.new("$", "declarations", "1.6") if !bom.declarations.nil? && newer?("1.6", sv)

      if md = bom.metadata
        result << Violation.new("$.metadata", "lifecycles", "1.5") if !md.lifecycles.nil? && newer?("1.5", sv)
      end

      bom.components.each_with_index do |comp, i|
        collect_component_violations(comp, "$.components[#{i}]", sv, result)
      end

      if md = bom.metadata
        if comp = md.component
          collect_component_violations(comp, "$.metadata.component", sv, result)
        end
      end

      result
    end

    private def self.collect_component_violations(comp, path : String, sv : String, result : Array(Violation)) : Nil
      # field name => {present?, minimum version}
      fields = {
        "modelCard"        => {!comp.model_card.nil?, "1.5"},
        "data"             => {!comp.data.nil?, "1.5"},
        "tags"             => {!comp.tags.nil?, "1.6"},
        "omniborId"        => {!comp.omnibor_id.nil?, "1.6"},
        "swhid"            => {!comp.swhid.nil?, "1.6"},
        "cryptoProperties" => {!comp.crypto_properties.nil?, "1.6"},
        "manufacturer"     => {!comp.manufacturer.nil?, "1.6"},
        "authors"          => {!comp.authors.nil?, "1.6"},
      }
      fields.each do |field, (present, min)|
        result << Violation.new(path, field, min) if present && newer?(min, sv)
      end

      collect_license_violations(comp, path, sv, result)

      if sub = comp.components
        sub.each_with_index do |c, i|
          collect_component_violations(c, "#{path}.components[#{i}]", sv, result)
        end
      end
    end

    private def self.collect_license_violations(comp, path : String, sv : String, result : Array(Violation)) : Nil
      licenses = comp.licenses
      return unless licenses

      licenses.each_with_index do |lic, i|
        lp = "#{path}.licenses[#{i}]"
        result << Violation.new(lp, "bom-ref", "1.6") if !lic.bom_ref.nil? && newer?("1.6", sv)
        result << Violation.new(lp, "acknowledgement", "1.6") if !lic.acknowledgement.nil? && newer?("1.6", sv)
      end
    end
  end
end
