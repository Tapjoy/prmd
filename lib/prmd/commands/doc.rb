def extract_attributes(schema, properties)
  attributes = []
  properties.each do |key, value|
    # found a reference to another element:
    _, value = schema.dereference(value)
    if value.has_key?('anyOf')
      descriptions = []
      examples = []

      # sort anyOf! always show unique identifier first
      anyof = value['anyOf'].sort_by do |property|
        property['$ref'].split('/').last.gsub('id', 'a')
      end

      anyof.each do |ref|
        _, nested_field = schema.dereference(ref)
        descriptions << nested_field['description']
        examples << nested_field['example']
      end

      # avoid repetition :}
      if descriptions.size > 1
        descriptions.first.gsub!(/ of (this )?.*/, "")
        descriptions[1..-1].map { |d| d.gsub!(/unique /, "") }
      end

      last = descriptions.pop
      description = [descriptions.join(", "), last].join(" or ")

      example = doc_example(*examples)
      attributes << [key, "string", description, example]

    # found a nested object
    elsif value['type'] == ['object'] && value['properties']
      nested = extract_attributes(schema, value['properties'])
      nested.each do |attribute|
        attribute[0] = "#{key}:#{attribute[0]}"
      end
      attributes.concat(nested)
    # just a regular attribute
    else
      description = value['description']
      if value['enum']
        description += '<br/><b>one of:</b>' + doc_example(*value['enum'])
      end
      example = doc_example(value['example'])
      attributes << [key, doc_type(value), description, example]
    end
  end
  return attributes
end

def doc_type(property)
  property_type = property["type"]
  #not all documents have to have a "type"
  if property_type.nil?
    return ""
  end
  schema_type = property_type.dup
  type = "nullable " if schema_type.delete("null")
  type.to_s + (property["format"] || schema_type.first)
end

def doc_example(*examples)
  examples.map { |e| "<code>#{e.to_json}</code>" }.join(" or ")
end

module Prmd
  def self.doc(schema, options={})
    #assumes there's a links element in the root that we can use to figure root_url
    #turns out schema doesnt need to have this to be 'valid', so don't assume so.
    links = schema['links']
    root_url = links.find{|l| l['rel'] == 'self'}['href'] if links
    root_url = '' if root_url.nil?

    doc = (options[:prepend] || []).map do |path|
      File.open(path, 'r').read + "\n"
    end

    doc << schema['definitions'].map do |_, definition|
      next if (definition['links'] || []).empty?
      resource = definition['id'].split('/').last
      serialization = {}
      if definition['definitions'].has_key?('identity')
        identifiers = if definition['definitions']['identity'].has_key?('anyOf')
          definition['definitions']['identity']['anyOf']
        else
          [definition['definitions']['identity']]
        end

        identifiers = identifiers.map {|ref| ref['$ref'].split('/').last }
      end
      if definition['properties']
        definition['properties'].each do |key, value|
          _, value = schema.dereference(value)
          if value.has_key?('properties')
            serialization[key] = {}
            value['properties'].each do |k,v|
              serialization[key][k] = schema.dereference(v).last['example']
            end
          else
            serialization[key] = value['example']
          end
        end
      else
        serialization.merge!(definition['example'])
      end

      title = definition['title'].split(' - ', 2).last

      Erubis::Eruby.new(File.read(File.dirname(__FILE__) + "/../views/endpoint.erb")).result({
        definition:      definition,
        identifiers:     identifiers,
        resource:        resource,
        root_url:        root_url,
        schema:          schema,
        serialization:   serialization,
        title:           title,
        params_template: File.read(File.dirname(__FILE__) + "/../views/parameters.erb"),
      }) + "\n"
    end
  end
end
