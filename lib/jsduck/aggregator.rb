require 'jsduck/class'
require 'jsduck/accessors'

module JsDuck

  # Combines JavaScript Parser, DocParser and Merger.
  # Produces array of classes as result.
  class Aggregator
    def initialize
      @documentation = []
      @classes = {}
      @orphans = []
      @current_class = nil
    end

    # Combines chunk of parsed JavaScript together with previously
    # added chunks.  The resulting documentation is accumulated inside
    # this class and can be later accessed through #result method.
    #
    # - file  SoureFile class instance
    #
    def aggregate(file)
      @current_class = nil
      file.each {|doc| register(doc) }
    end

    # Registers documentation node either as class or as member of
    # some class.
    def register(node)
      if node[:tagname] == :class
        add_class(node)
      else
        add_member(node)
      end
    end

    # When class exists, merge it with class node.
    # Otherwise add as new class.
    def add_class(cls)
      old_cls = @classes[cls[:name]]
      if old_cls
        merge_classes(old_cls, cls)
        @current_class = old_cls
      else
        @current_class = cls
        @documentation << cls
        @classes[cls[:name]] = cls
        insert_orphans(cls)
      end
    end

    # Merges new class-doc into old one.
    def merge_classes(old, new)
      [:extends, :singleton, :private, :protected].each do |tag|
        old[tag] = old[tag] || new[tag]
      end
      [:mixins, :alternateClassNames].each do |tag|
        old[tag] = old[tag] + new[tag]
      end
      new[:xtypes].each_pair do |key, xtypes|
        old[:xtypes][key] = (old[:xtypes][key] || []) + xtypes
      end
      old[:doc] = old[:doc].length > 0 ? old[:doc] : new[:doc]
      # Additionally the doc-comment can contain configs and constructor
      old[:members][:cfg] += new[:members][:cfg]
      old[:members][:method] += new[:members][:method]
    end

    # Tries to place members into classes where they belong.
    #
    # @member explicitly defines the containing class, but we can meet
    # item with @member=Foo before we actually meet class Foo - in
    # that case we register them as orphans.  (Later when we finally
    # meet class Foo, orphans are inserted into it.)
    #
    # Items without @member belong by default to the preceding class.
    # When no class precedes them - they too are orphaned.
    def add_member(node)
      if node[:owner]
        if @classes[node[:owner]]
          add_to_class(@classes[node[:owner]], node)
        else
          add_orphan(node)
        end
      elsif @current_class
        node[:owner] = @current_class[:name]
        add_to_class(@current_class, node)
      else
        add_orphan(node)
      end
    end

    def add_to_class(cls, member)
      cls[member[:static] ? :statics : :members][member[:tagname]] << member
    end

    def add_orphan(node)
      @orphans << node
    end

    # Inserts available orphans to class
    def insert_orphans(cls)
      members = @orphans.find_all {|node| node[:owner] == cls[:name] }
      members.each do |node|
        add_to_class(cls, node)
        @orphans.delete(node)
      end
    end

    # Creates classes for orphans that have :owner property defined,
    # and then inserts orphans to these classes.
    def classify_orphans
      @orphans.each do |orph|
        if orph[:owner]
          class_name = orph[:owner]
          if !@classes[class_name]
            add_empty_class(class_name)
          end
          add_member(orph)
          @orphans.delete(orph)
        end
      end
    end

    # Creates class with name "global" and inserts all the remaining
    # orphans into it (but only if there are any orphans).
    def create_global_class
      return if @orphans.length == 0

      add_empty_class("global", "Global variables and functions.")
      @orphans.each do |orph|
        orph[:owner] = "global"
        add_member(orph)
      end
      @orphans = []
    end

    def add_empty_class(name, doc = "")
      add_class({
        :tagname => :class,
        :name => name,
        :doc => doc,
        :mixins => [],
        :alternateClassNames => [],
        :members => Class.default_members_hash,
        :statics => Class.default_members_hash,
        :filename => "",
        :html_filename => "",
        :linenr => 0,
      })
    end

    # Appends Ext4 options parameter to each event parameter list.
    # But only when we are dealing with Ext4 codebase.
    def append_ext4_event_options
      return unless ext4?

      options = {
        :tagname => :param,
        :name => "eOpts",
        :type => "Object",
        :doc => "The options object passed to {@link Ext.util.Observable#addListener}."
      }
      @classes.each_value do |cls|
        cls[:members][:event].each {|e| e[:params] << options }
      end
    end

    # Creates accessor method for configs marked with @accessor
    def create_accessors
      accessors = Accessors.new
      @classes.each_value do |cls|
        accessors.create(cls)
      end
    end

    # Are we dealing with ExtJS 4?
    # True if any of the classes is defined with Ext.define()
    def ext4?
      @documentation.any? {|cls| cls[:code_type] == :ext_define }
    end

    def result
      @documentation + @orphans
    end
  end

end
