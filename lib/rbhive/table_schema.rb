module RBHive
  class TableSchema
    attr_accessor :name
    attr_reader :columns, :partitions
    def initialize(name, comment=nil, options={}, &blk)
      @name, @comment = name, comment
      @location = options[:location] || nil
      @field_sep = options[:field_sep] || "\t"
      @line_sep = options[:line_sep] || "\n"
      @collection_sep = options[:collection_sep] || "|"
      @columns = []
      @partitions = []
      @clustering = nil
      @serde_name = nil
      @serde_properties = {}
      instance_eval(&blk) if blk
    end

    def column(name, type, comment=nil)
      @columns << Column.new(name, type, comment)
    end

    def partition(name, type, comment=nil)
      @partitions << Column.new(name, type, comment)
    end

    def clustered_by(columns, number_of_buckets, sort_by_clause=nil)
      @clustering = Clustering.new(columns, number_of_buckets, sort_by_clause)
    end

    def serde(name, properties={})
      @serde_name = name
      @serde_properties = properties
    end

    def create_table_statement()
      %[CREATE #{external}TABLE #{table_statement}
  ROW FORMAT #{row_format_statement}
  STORED AS TEXTFILE
  #{location}]
    end

    def row_format_statement
      if @serde_name
        serde_statement
      else
        delimited_statement
      end
    end

    def delimited_statement
      %(DELIMITED
  FIELDS TERMINATED BY '#{@field_sep}'
  COLLECTION ITEMS TERMINATED BY '#{@collection_sep}'
  LINES TERMINATED BY '#{@line_sep}')
    end

    def serde_statement
      %(SERDE '#{@serde_name}'\n#{serde_properties_statement})
    end

    def serde_properties_statement
      return '' unless @serde_properties.any?
      kvs = @serde_properties.map { |k,v| %("#{k}" = "#{v}") }.join(",\n")
      %(WITH SERDEPROPERTIES (#{kvs}))
    end

    def replace_columns_statement
      alter_columns_statement("REPLACE")
    end

    def add_columns_statement
      alter_columns_statement("ADD")
    end

    def to_s
      table_statement
    end

    private

    def external
      @location.nil? ? '' : 'EXTERNAL '
    end

    def table_statement
      comment_string = (@comment.nil? ? '' : " COMMENT '#{@comment}'")
      %[`#{@name}` #{column_statement}#{comment_string}\n#{partition_statement}\n#{clustering_statement}]
    end

    def location
      @location.nil? ? '' : "LOCATION '#{@location}'"
    end

    def alter_columns_statement(add_or_replace)
      %[ALTER TABLE `#{name}` #{add_or_replace} COLUMNS #{column_statement}]
    end

    def column_statement
      cols = @columns.join(",\n")
      "(\n#{cols}\n)"
    end

    def partition_statement
      return "" if @partitions.nil? || @partitions.empty?
      cols = @partitions.join(",\n")
      "PARTITIONED BY (\n#{cols}\n)"
    end

    def clustering_statement
      return "" if @clustering.nil?
      @clustering.statement
    end

    class Column
      attr_reader :name, :type, :comment
      def initialize(name, type, comment=nil)
        @name, @type, @comment = name, type, comment
      end

      def to_s
        comment_string = @comment.nil? ? '' : " COMMENT '#{@comment}'"
        "`#{@name}` #{@type.to_s.upcase}#{comment_string}"
      end
    end

    class Clustering
      attr_reader :columns, :sort_by_clause, :number_of_buckets
      def initialize columns, number_of_buckets, sort_by_clause
        @columns = [*columns]
        @number_of_buckets = number_of_buckets
        @sort_by_clause = sort_by_clause
      end

      def statement
        sort_clause = sort_by_clause.nil? ? '' : "SORTED BY (#{@sort_by_clause}) "
        "CLUSTERED BY (#{@columns.join(', ')}) #{sort_clause}INTO #{@number_of_buckets} BUCKETS"
      end
    end
  end
end
