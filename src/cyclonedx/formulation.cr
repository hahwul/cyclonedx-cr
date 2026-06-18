require "json"
require "xml"
require "./models"

module CycloneDX
  # A single executed command within a step. Per the schema a `command` is an
  # object (`{executed, properties}`), not a bare string.
  class StepCommand
    include JSON::Serializable

    getter executed : String?
    getter properties : Array(Property)?

    def initialize(@executed : String? = nil, @properties : Array(Property)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("command") do
        if executed = @executed
          xml.element("executed") { xml.text executed }
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class TaskStep
    include JSON::Serializable

    getter name : String?
    getter description : String?
    getter commands : Array(StepCommand)?

    def initialize(@name : String? = nil, @description : String? = nil,
                   @commands : Array(StepCommand)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("step") do
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if commands_val = @commands
          xml.element("commands") do
            commands_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Task
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter uid : String?
    getter name : String?
    getter description : String?
    @[JSON::Field(key: "taskTypes")]
    getter task_types : Array(String)?
    getter steps : Array(TaskStep)?
    getter properties : Array(Property)?

    VALID_TASK_TYPES = [
      "copy", "clone", "lint", "scan", "merge", "build",
      "test", "deliver", "deploy", "release", "clean", "other",
    ]

    def initialize(@uid : String? = nil, @name : String? = nil,
                   @description : String? = nil, @task_types : Array(String)? = nil,
                   @steps : Array(TaskStep)? = nil, @properties : Array(Property)? = nil,
                   @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("task", attributes: attrs) do
        if uid = @uid
          xml.element("uid") { xml.text uid }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if types = @task_types
          xml.element("taskTypes") do
            types.each { |t| xml.element("taskType") { xml.text t } }
          end
        end
        if steps_val = @steps
          xml.element("steps") do
            steps_val.each(&.to_xml(xml))
          end
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Workflow
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter uid : String?
    getter name : String?
    getter description : String?
    getter tasks : Array(Task)?
    @[JSON::Field(key: "taskTypes")]
    getter task_types : Array(String)?
    getter properties : Array(Property)?

    def initialize(@uid : String? = nil, @name : String? = nil,
                   @description : String? = nil, @tasks : Array(Task)? = nil,
                   @task_types : Array(String)? = nil,
                   @properties : Array(Property)? = nil, @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("workflow", attributes: attrs) do
        if uid = @uid
          xml.element("uid") { xml.text uid }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if tasks_val = @tasks
          xml.element("tasks") do
            tasks_val.each(&.to_xml(xml))
          end
        end
        # taskTypes is required by the workflowType schema and follows `tasks`
        # in the <sequence>.
        if types = @task_types
          xml.element("taskTypes") do
            types.each { |t| xml.element("taskType") { xml.text t } }
          end
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Formula
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter workflows : Array(Workflow)?
    getter properties : Array(Property)?

    def initialize(@workflows : Array(Workflow)? = nil,
                   @properties : Array(Property)? = nil,
                   @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("formula", attributes: attrs) do
        if workflows_val = @workflows
          xml.element("workflows") do
            workflows_val.each(&.to_xml(xml))
          end
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end
end
