module ArkanisDevelopmentCompat
  module SimpleLocalization
    module Language
      class << self
        # Returns the specified entry from the currently used language file.
        # It's possible to specify nested entries by using more than one
        # parameter.
        # 
        #   Language.entry :active_record_messages, :too_short  # => "ist zu kurz (mindestens %d Zeichen)."
        # 
        # This will return the +too_short+ entry within the +active_record_messages+
        # entry. The YAML code in the language file looks like this:
        # 
        #   active_record_messages:
        #     too_short: ist zu kurz (mindestens %d Zeichen).
        # 
        # If the entry is not found +nil+ is returned.
        # 
        # This method also allows you to substitute values inside the found
        # entry. The +substitute_entry+ method is used for this and there are
        # two ways to do this:
        # 
        # With +format+:
        # 
        # Just specify an array with the format values as last key:
        # 
        #   Language.entry :active_record_messages, :too_short, [5] # => "ist zu kurz (mindestens 5 Zeichen)."
        # 
        # If +format+ fails the reaction depends on the +debug+ option of the
        # Language module. If +debug+ is set to +false+ the unformatted entry is
        # returned. If +debug+ is +true+ an +EntryFormatError+ is raised
        # detailing what went wrong.
        # 
        # With "hash notation" like used by the ActiveRecord conditions:
        # 
        # It's also possible to use a hash to specify the values to substitute.
        # This works like the conditions of ActiveRecord:
        # 
        #   app:
        #     welcome: Welcome :name, you have :number new messages.
        # 
        #   Language.entry :app, :welcome, :name => 'Mr. X', :number => 5  # => "Welcome Mr. X, you have 5 new messages."
        # 
        # Both approaches allow you to use the \ character to escape colons (:)
        # and percent sings (%).
        
        # def entry(*args)
        #   entry!(*args)
        # end

        # Same as the +Language#entry+ method but it raises an +EntryNotFound+
        # exception if the specified entry does not exists.
        #
        # If the format style is used and an error occurs an +EntryFormatError+
        # will be raised. It contains some extra information as well as the
        # original exception.
        def entry!(*args)
          options = {}
          if args.last.kind_of?(Hash)
            options.merge! args.pop
          elsif args.last.kind_of?(Array)
            raise "Array syntax not supported yet (TODO)"
          end
          
          # By now *args only contains the path info, with the last item being the key itself
          
          key = args.pop
          
          if args.size > 0
            options.merge! :scope => args
          end
          
          I18n.translate key, options
        end
        
        alias_method :entry, :entry! # Exceptions are handled well by Rails i18n itself
        alias_method :[], :entry
      end
    end
  end
end

# = Localized application
# 
# This feature allows you to use the language file to localize your application.
# You can add your own translation strings to the +app+ section of the language
# file and read them with the +l+ global method. You can use this method in your
# controllers, views, mail templates, simply everywhere. To make the access more
# convenient you can use the +lc+ method in controllers, views, partials,
# models and observers.
# 
#   app:
#     title: Simple Localization Rails plugin
#     subtitle: The plugin should make it much easier to localize Ruby on Rails
#     headings:
#       wellcome: Wellcome to the RDoc Documentation of this plugin
# 
#   l(:title) # => "Simple Localization Rails plugin"
#   l(:headings, :wellcome) # => "Wellcome to the RDoc Documentation of this plugin"
# 
# The +l+ method is just like the 
# ArkanisDevelopment::SimpleLocalization::Language#entry method but is limited
# to the +app+ section of the language file.
# 
# To save some work you can narrow down the scope of the +l+ method even
# further by using the +l_scope+ method:
# 
#   app:
#     layout:
#       nav:
#         main:
#           home: Homepage
#           contact: Contact
#           login: Login
# 
#   l :layout, :nav, :main, :home     # => "Homepage"
#   l :layout, :nav, :main, :contact  # => "Contact"
# 
# Same as
# 
#   l_scope :layout, :nav, :main do
#     l :home     # => "Homepage"
#     l :contact  # => "Contact"
#   end
# 
# Please also take a look at the <code>ContextSensetiveHelpers::lc</code>
# method. It can make life much more easier.
# 
# == Used sections of the language file
# 
# This feature uses the +app+ section of the language file. This section is
# reserved for localizing your application and you can create entries in
# this section just as you need it.
# 
#   app:
#     index:
#       title: Wellcome to XYZ
#       subtitle: Have a nice day...
#     projects:
#       title: My Projects
#       subtitle: This is a list of projects I'm currently working on
# 
#   l(:index, :title) # => "Wellcome to XYZ"
#   l(:projects, :subtitle) # => "This is a list of projects I'm currently working on"
# 

module ArkanisDevelopmentCompat::SimpleLocalization #:nodoc:


  module LocalizedModelAttributes
    def self.included(base)
      base.class_eval do
        include(InstanceMethods)
        attribute_method_suffix '_localized', '_localized='
      end
    end

    class Helper
      include Singleton
      include ActionView::Helpers::NumberHelper
    end

    module InstanceMethods
      private
        def attribute_localized(attribute_name)
          attribute_value = send(attribute_name)
          column = self.class.columns_hash[attribute_name]

          case column.type
            when :date: localize_date(attribute_value)
            when :datetime: localize_datetime(attribute_value)
            when :float, :integer: localize_number(attribute_value)
            when :decimal: localize_number(attribute_value, column.scale)
            else attribute_value
          end
        end

        def attribute_localized=(attribute_name, new_attribute_value)
          send "#{attribute_name}=", case self.class.columns_hash[attribute_name].type
            when :date: parse_localized_date(new_attribute_value)
            when :datetime: parse_localized_datetime(new_attribute_value)
            when :float: parse_localized_number(new_attribute_value, :to_f)
            when :decimal: parse_localized_number(new_attribute_value, :to_d)
            when :integer: parse_localized_number(new_attribute_value, :to_i)
            else new_attribute_value
          end
        end

        def parse_localized_date(loc_date)
          return if loc_date.blank?
          (Date.strptime(loc_date, Language[:date, :formats][:attributes])).to_date
        end

        def parse_localized_datetime(loc_date)
          return if loc_date.blank?
          (DateTime.strptime(loc_date, Language[:time, :formats][:attributes])).to_time
        end

        def parse_localized_number(loc_number, type_cast)
          return if loc_number.blank?
          loc_number.to_s.gsub(Language[:number, :format, :delimiter], '').gsub(Language[:number, :format, :separator], '.').send(type_cast)
        end

        def localize_date(date)
          return if date.blank?
          I18n.localize date, :format => :attributes
        end

        def localize_datetime(datetime)
          return if datetime.blank?
          I18n.localize datetime, :format => :attributes
        end

        def localize_number(number, options = { })
          return if number.blank?
          Helper.instance.number_with_precision(number, options)
        end
    end
  end

  module LocalizedApplication #:nodoc:
    
    # This module will extend the ArkanisDevelopment::SimpleLocalization::Language
    # class with all necessary class methods.
    module Language
      
      # Class variable to hold the scope stack of the +app_with_scope+ method.
      @@app_scope_stack = []
      
      # Basically the same as the +app_not_scoped+ method but +app_scoped+ does
      # respect the scope set by the +app_with_scope+ method.
      # 
      # Assuming the following language file data:
      # 
      #   app_default_value: No translation available
      #   app:
      #     index:
      #       title: Welcome to XYZ
      #       subtitle: Have a nice day...
      # 
      # The following code would output:
      # 
      #   Language.app_with_scope :index do
      #     Language.app_scoped :title            # => "Welcome to XYZ"
      #     Language.app_scoped :subtitle         # => "Have a nice day..."
      #     Language.app_scoped "I don't exist"   # => "I don't exist"
      #   end
      #   
      #   Language.app_scoped :index, :title    # => "Welcome to XYZ"
      #   Language.app_scoped :not_existing_key # => "No translation available"
      # 
      def app_scoped(*keys)
        self.app_not_scoped(*(@@app_scope_stack.flatten + keys))
      end
      
      # This class method is used to access entries used by the localized
      # application feature. Since the +app+ section of the language file is
      # reserved for this feature this method restricts the scope of the entries
      # available to the +app+ section. The method should only be used for
      # application localization and therefor there is no need to access other
      # sections of the language file with this method.
      # 
      #   app_default_value: No translation available
      #   app:
      #     index:
      #       title: Welcome to XYZ
      #       subtitle: Have a nice day...
      # 
      #   Language.app_not_scoped(:index, :subtitle) # => "Have a nice day..."
      # 
      # If the specified entry does not exists a default value is returned. If
      # the last argument specified is a string this string is returned as
      # default value. Assume the same language file data as above:
      # 
      #   Language.app_not_scoped(:index, "Welcome to my app") # => "Welcome to my app"
      # 
      # The <code>"Welcome to my app"</code> entry doesn't exists in the
      # language file. Because the last argument is a string it will returned as
      # a default value. If the last argument isn't a string the method will
      # return the +app_default_value+ entry of the language file. Again, same
      # language file data as above:
      # 
      #   Language.app_not_scoped(:index, :welcome) # => "No translation available"
      # 
      # The <code>:welcome</code> entry does not exists. The last argument isn't
      # a string and therefore the value of the +app_default_value+ entry is
      # returned. If this fall back entry does not exists +nil+ is returned.
      # 
      # This method does not respect the scope set by the +with_app_scope+
      # method. This is done by the +app_scoped+ method.
      def app_not_scoped(*keys)
        self.entry(:app, *keys) || begin
          substitution_args = keys.last.kind_of?(Array) || keys.last.kind_of?(Hash) ? keys.pop : []
          if keys.last.kind_of?(String)
            self.substitute_entry keys.last, substitution_args
          else
            # self.entry(:app_default_value)
            keys.inspect
          end
        end
      end
      
      # Narrows down the scope of the +app_scoped+ method. Useful if you have a
      # very nested language file and don't want to use the +lc+ helpers:
      # 
      #   app:
      #     layout:
      #       nav:
      #         main:
      #           home: Homepage
      #           contact: Contact
      #           about: About
      # 
      # Usually the calls to the +app_scoped+ method would look like this:
      # 
      #   Language.app_scoped :layout, :nav, :main, :home     # => "Homepage"
      #   Language.app_scoped :layout, :nav, :main, :contact  # => "Contact"
      #   Language.app_scoped :layout, :nav, :main, :about    # => "About"
      # 
      # In this situation you can use +with_app_scope+ to save some work:
      # 
      #   Language.with_app_scope :layout, :nav, :main do
      #     Language.app_scoped :home     # => "Homepage"
      #     Language.app_scoped :contact  # => "Contact"
      #     Language.app_scoped :about    # => "About"
      #   end
      # 
      # Every call to the +app_scoped+ method inside the block will
      # automatically be prefixed with the sections you specified to the
      # +with_app_scope+ method.
      def with_app_scope(*scope_sections, &block)
        @@app_scope_stack.push scope_sections
        begin
          yield
        ensure
          @@app_scope_stack.pop
        end
      end
      
      # Added aliases for backward compatibility (pre 2.4 versions).
      alias_method :app, :app_scoped
      alias_method :app_with_scope, :with_app_scope
      
      # A shortcut for creating a CachedLangSectionProxy object. Such a proxy
      # is a object which redirects almost all messages to a specific entry of
      # the currently selected language.
      # 
      # Assume German and English language files like this:
      # 
      # de.yml
      # 
      #   app:
      #     title: Deutscher Test
      #     options: [dies, das, jenes]
      # 
      # en.yml
      # 
      #   app:
      #     title: English test
      #     options: [this, that, other stuff]
      # 
      # Now we can create a proxy object for these entries and switch between
      # languages:
      # 
      #   @title = Language.app_proxy :title
      #   @options = Language.app_proxy :options, :orginal_receiver => []
      #   
      #   # no language file loaded (this is what the <code>orginal_receiver</code> option is for, defaults to "")
      #   @title.inspect  # => ""
      #   @options.inspect  # => []
      #   
      #   # now with switching
      #   Language.use :de
      #   @title.inspect  # => "Deutscher Test"
      #   @options.inspect  # => ["dies", "das", "jenes"]
      #   
      #   Language.use :en
      #   @title.inspect  # => "English test"
      #   @options.inspect  # => ["this", "that", "other stuff"]
      # 
      # This all happens without changing the actual <code>@title</code> or
      # <code>@options</code> variable. So to speek a proxy fakes a simple
      # variable but it's value is exchanged dependend on the current language.
      # 
      # This is actually very useful if a method expects just one variable at
      # the application startup and thus doesn't support language switching,
      # e.g. the message parameter of the +validates_presence_of+ method (here
      # the global +l_proxy+ shortcut for <code>Language.app_proxy</code> is
      # used):
      # 
      #   class Something < ActiveRecord::Base
      #     
      #     validates_presence_of :name, :message => l_proxy(:messages, :name_required)
      #     
      #   end
      # 
      # Now the error message added by +validates_presence_of+ will also be
      # switched if the language is switched. This is a very efficient way to
      # inject language switching code into methods not made for language
      # switching and is used by many other features of this plugin.
      def app_proxy(*keys)
        ProxyObject.new(:app, *keys)
      end
    end
    
    # This module defines global helper methods and therefor will be
    # included into the Object class.
    module GlobalHelpers
      
      # Defines a global shortcut for the Language#app_scoped method.
      def ll(*sections)
        ArkanisDevelopmentCompat::SimpleLocalization::Language.app_scoped(*sections)
      end

      # Defines a global shortcut for the Language#app_not_scoped method.
      def lnc(*sections)
        ArkanisDevelopmentCompat::SimpleLocalization::Language.app_not_scoped(*sections)
      end

      # The global shortcut for the Language#with_app_scope method.
      def l_scope(*sections, &block)
        ArkanisDevelopmentCompat::SimpleLocalization::Language.with_app_scope(*sections, &block)
      end
      
      # A global shortcut for the Language#app_proxy method.
      def l_proxy(*sections)
        ArkanisDevelopmentCompat::SimpleLocalization::Language.app_proxy(*sections)
      end
    end
    
    module ContextSensetiveHelpers
      
      # This helper provides a short way to access nested language entries by
      # automatically adding a scope to the specified keys. This scope depends
      # on where you call this helper from. If called in the
      # +users_controller.rb+ file it will add <code>:users</code> to it.
      # 
      # This is done by analysing the call stack of the method and there are a
      # few more possibilities:
      # 
      # in <code>app/controllers/users_controller.rb</code>
      # 
      #   lc(:test)  # => will be the same as l(:users, :test)
      # 
      # in <code>app/controllers/projects/tickets_controller.rb</code>
      # 
      #   lc(:test)  # => will be the same as l(:projects, :tickets, :test)
      # 
      # in <code>app/views/users/show.rhtml</code>
      # 
      #   lc(:test)  # => will be the same as l(:users, :show, :test)
      # 
      # in <code>app/views/users/_summary.rhtml</code>
      # 
      #   lc(:test)  # => will be the same as l(:users, :summary, :test)
      # 
      # in <code>app/models/user.rb</code>
      # 
      #   lc(:test)  # => will be the same as l(:user, :test)
      # 
      # in <code>app/models/user_observer.rb</code>
      # 
      #   lc(:test)  # => will be the same as l(:user, :test)
      # 
      def lc(*args)
        args.unshift *get_scope_of_context
        ArkanisDevelopmentCompat::SimpleLocalization::Language.app_not_scoped *args
      end
      
      # A context sensetive shortcut for the Language#app_proxy method.
      def lc_proxy(*args)
        args.unshift *get_scope_of_context
        ArkanisDevelopmentCompat::SimpleLocalization::Language.app_proxy(*args)
      end
      
      private
      
      # Analyses the call stack to find the rails application file (files in the
      # +app+ directory of the rails application) the context sensitive helper
      # is called in.
      # 
      # You can inject a faked call stack by using the $lc_test_get_scope_of_context_stack
      # global variable. The method will then use this instead of the real call
      # stack. This is handy for testing.
      def get_scope_of_context
        stack_to_analyse = $lc_test_get_scope_of_context_stack || caller
        app_dirs = '(helpers|controllers|views|models)'
        latest_app_file = stack_to_analyse.detect { |level| level =~ /.*\/app\/#{app_dirs}\// }
        return [] unless latest_app_file
        
        path = latest_app_file.match(/([^:]+):\d+.*/)[1]
        dir, file = path.match(/.*\/app\/#{app_dirs}\/(.+)#{Regexp.escape(File.extname(path))}$/)[1, 2]
        
        scope = file.split('/')
        case dir
        when 'controllers'
          scope.last.gsub! /_controller$/, ''
        when 'helpers'
          scope.last.gsub! /_helper$/, ''
        when 'views'
          scope.last.gsub! /^_/, ''        # remove the leading underscore from partial templates
          scope.last.gsub! /\.[^\.]*$/, '' # take off the mime type
        when 'models'
          scope.last.gsub! /_observer$/, ''
        end
        
        scope
      end
      
    end
    
  end
end



ArkanisDevelopmentCompat::SimpleLocalization::Language.send :extend, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::Language

Object.send :include, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::GlobalHelpers
ActionController::Base.send :extend, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::ContextSensetiveHelpers
ActionController::Base.send :include, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::ContextSensetiveHelpers
ActiveRecord::Base.send :extend, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::ContextSensetiveHelpers
ActiveRecord::Base.send :include, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::ContextSensetiveHelpers
ActionView::Base.send :include, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedApplication::ContextSensetiveHelpers
ActiveRecord::Base.send :include, ArkanisDevelopmentCompat::SimpleLocalization::LocalizedModelAttributes
