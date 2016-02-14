module Jekyll
    class Site
      attr_accessor :menu
    end

    class Page
        def menu
            self.data['menu'] ||= {}
        end
        
        def menu_parent
            menu['parent']
        end
        
        def menu_name
            menu['name'] ||= self.data['title']
        end
        
        def subpages
            menu['subpages'] ||= []
        end
    end

    class MenuGenerator < Generator
        safe true
        
        def menu_name(hash)
            hash['menu']['name'] || hash['title']
        end

        def setup_config(site)
            site.config['menu_generator'] ||= {}
            site.config['menu_generator']['parent_match_hash'] ||= 'path'
            site.config['menu_generator']['menu_root'] ||= '__root'
            site.config['menu_generator']['delete_content_hash'] ||= false
            site.config['menu_generator']['hash_name_in_site_config'] ||= "menu"
            site.config['menu_generator']['multi_menu'] ||= false

            site.config['menu_generator']['css'] ||= {}
            site.config['menu_generator']['css']['current'] ||= 'current'
            site.config['menu_generator']['css']['current_parent'] ||= 'current-parent'
            site.config['menu_generator']['css']['li'] ||= ''
            site.config['menu_generator']['css']['ul'] ||= ''

            @parent_match_hash          = site.config['menu_generator']['parent_match_hash']
            @menu_root                  = site.config['menu_generator']['menu_root']
            @multi_menu                 = site.config['menu_generator']['multi_menu']
            @delete_content_hash        = site.config['menu_generator']['delete_content_hash']
            @hash_name_in_site_config   = site.config['menu_generator']['hash_name_in_site_config']
        end

        def generate(site)
            @pages = site.pages.dup

            setup_config(site)

            @lookup = {}
            @menues = []

            build_tree
            sort_pages
            generate_suburls
            publish_menues(site)
            
        end
        
        def publish_menues(site)
            if 0 == @menues.length
                site.config[@hash_name_in_site_config] = []
                site.menu = []
            else
                if @multi_menu
                    menu = {}
                    @menues.each do |menu_name|
                        menu[menu_name] = @lookup[@menu_root + menu_name]
                    end

                    site.config[@hash_name_in_site_config] = menu
                    site.menu = menu
                else
                    site.config[@hash_name_in_site_config] = @lookup[@menu_root]
                    site.menu = @lookup[@menu_root]
                end
            end
        end

        def getParentInLookup(parent)
            if @lookup.has_key?(parent)
                return @lookup[parent]
            end

            if not parent.nil? and parent.start_with?(@menu_root)
                if @multi_menu
                    str_start = @menu_root.length
                    str_end = parent.length
                    menu_name = parent[str_start..str_end]
                    @menues << menu_name
                    @lookup[parent] = []
                    return @lookup[parent] 
                else
                    if parent == @menu_root
                        @lookup[parent] = []
                        @menues << ''
                        return @lookup[@menu_root]
                    end
                end
            end

            return nil
        end

        def build_tree
            # build the subpage tree
            loop do 
                prev_size = @pages.size
                
                @pages.reject! do |page|
                    parent = getParentInLookup(page.menu_parent)
                    unless parent.nil?
                        # Initilize the name
                        page.menu_name
                        @lookup[page[@parent_match_hash]] = page.subpages
                        liq_hash = page.to_liquid

                        if @delete_content_hash
                            liq_hash.delete('content')
                        end
                        parent << liq_hash
                        true
                    else
                        false
                    end
                end
                
                break if @pages.size == prev_size
            end
        end
        
        def sort_pages
            # lookup contains every page's subpage array,
            # so we only need to sort every value in lookup
            @lookup.each do |key, val|
                val.sort! do |a, b|
                    compare_pages(a, b)  
                end
            end
        end
        
        def compare_pages(a, b)
            if a['menu']['position'].nil? and b['menu']['position'].nil? or a['menu']['position'] == b['menu']['position']
                # neither has a position, sort by name
                menu_name(a) <=> menu_name(b)
            elsif a['menu']['position'].nil?
                # if a has no position, it goes after b
                +1
            elsif b['menu']['position'].nil?
                # if b has no position, it goes after a
                -1
            else
                # both have a position, compare them
                a['menu']['position'] <=> b['menu']['position']
            end  
        end
        
        def generate_suburls
            # generate the suburl lists.
            # #set_suburls recurses, so we only call this
            # on the pages in the main menu
            @menues.each do |menu_name|
                @lookup[@menu_root + menu_name].each do |page|
                    set_suburls(page)
                end
            end
            
        end
        
        def set_suburls(page)
            page['menu']['subpages'].each do |subpage|
                set_suburls(subpage)
            end
            page['menu']['suburls'] = suburls(page)
        end
        
        def suburls(page_hash, add_self=false)
            subsub = page_hash['menu']['subpages'].map do |subpage|
                suburls(subpage, true)
            end
            subsub.flatten!
            if add_self
                subsub << page_hash['url']
            else
                subsub
            end
        end
    end 

  class MenuGeneratorTag < Liquid::Tag

    Syntax = /^\s*(max_depth:[0-9]+)?\s*$/ 

    def initialize(tag_name, markup, tokens)
      @attributes = {}
      
      # Parse parameters
      if markup =~ Syntax
        markup.scan(Liquid::TagAttributes) do |key, value|
          #p key + ":" + value
          @attributes[key] = value
        end
      else
        raise SyntaxError.new("Syntax Error in 'MenuGenerator' - Valid syntax: menu [max_depth:y]")
      end

      @max_depth = @attributes['max_depth'].nil? ? -1 : @attributes['max_depth'].to_i()
      
      super
    end

    def render(context)
      site = context.registers[:site]
      page = context.registers[:page]

      @css_class_current = site.config['menu_generator']['css']['current']
      @css_class_current_parent = site.config['menu_generator']['css']['current_parent']

      render_menu(site.menu, site, page)
    end

    def render_menu(menu, site, page, level=0)
      output = "<ul class=\"menu-level-#{level} " + site.config['menu_generator']['css']['ul'] +  "\">"

      menu.each do |menu_page|
        
        css_class = ""
        if page['url'] == menu_page['url']
          css_class = " class=\"" +  site.config['menu_generator']['css']['li'] + ' ' +  @css_class_current + "\""
        elsif menu_page['menu']['suburls'].include? page['url']
          css_class = " class=\"" +  site.config['menu_generator']['css']['li'] + ' ' + @css_class_current_parent + "\""  
        end 

        title = menu_page['menu']['name']
        url = menu_page['url']

        output += "<li#{css_class}><a href=\"#{url}\">#{title}</a>"

        unless menu_page['menu']['subpages'].count == 0 or level - @max_depth == 0
          output += render_menu(menu_page['menu']['subpages'], site, page, level + 1)
        end

        output += "</li>"

      end      

      output += "</ul>"

      output
    end

  end

end

Liquid::Template.register_tag('menu', Jekyll::MenuGeneratorTag)
