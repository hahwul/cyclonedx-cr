require "./bom"
require "./formulation"

module CycloneDX
  class ValidationError
    getter path : String
    getter message : String

    def initialize(@path : String, @message : String)
    end

    def to_s : String
      "#{@path}: #{@message}"
    end
  end

  class Validator
    getter errors : Array(ValidationError)

    def initialize
      @errors = [] of ValidationError
    end

    def validate(bom : BOM) : Bool
      @errors.clear
      validate_bom(bom)
      @errors.empty?
    end

    private def validate_bom(bom : BOM)
      add_error("$.bomFormat", "must be 'CycloneDX'") unless bom.bom_format == "CycloneDX"
      add_error("$.specVersion", "must be a supported version") unless BOM::SUPPORTED_VERSIONS.includes?(bom.spec_version)
      add_error("$.serialNumber", "must start with 'urn:uuid:'") unless bom.serial_number.starts_with?("urn:uuid:")

      bom.components.each_with_index do |comp, i|
        validate_component(comp, "$.components[#{i}]")
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
    end

    private def validate_component(comp : Component, path : String)
      add_error("#{path}.name", "must not be empty") if comp.name.empty?
      add_error("#{path}.version", "must not be empty") if comp.version.empty?

      unless Component::VALID_TYPES.includes?(comp.component_type)
        add_error("#{path}.type", "invalid type '#{comp.component_type}', valid: #{Component::VALID_TYPES.join(", ")}")
      end

      if scope = comp.scope
        unless Component::VALID_SCOPES.includes?(scope)
          add_error("#{path}.scope", "invalid scope '#{scope}'")
        end
      end

      if sub = comp.components
        sub.each_with_index do |c, i|
          validate_component(c, "#{path}.components[#{i}]")
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
      if lifecycles = metadata.lifecycles
        lifecycles.each_with_index do |lc, i|
          if phase = lc.phase
            unless Lifecycle::VALID_PHASES.includes?(phase)
              add_error("#{path}.lifecycles[#{i}].phase", "invalid phase '#{phase}'")
            end
          end
        end
      end
    end

    private def add_error(path : String, message : String)
      @errors << ValidationError.new(path, message)
    end
  end
end
