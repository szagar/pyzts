class Tags
  def initialize
    @tag_array = Array.new   # array of hashs, hash value optional
  end

  def add_tag(name,value=nil)
    tag = value ? "#{name}:#{value}" : name
    @tag_array << tag
  end

  def to_s
    @tag_array.join(";")
  end

  def parse(data)
    tag_hash = {}
    data.split(";").each do |tag|
      name,value =  tag.split(":")
      next unless name
      puts "tag_hash[#{name}] = #{value}"
      tag_hash[name] = value
    end
    puts "tag_hash=#{tag_hash}"
    tag_hash
  end
end
