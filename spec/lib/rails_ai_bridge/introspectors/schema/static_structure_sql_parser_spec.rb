# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::Schema::StaticStructureSqlParser do
  let(:config) { RailsAiBridge.configuration }

  def parse(content)
    described_class.new(content: content, config: config).call
  end

  # ---------------------------------------------------------------------------
  # Shape of the result
  # ---------------------------------------------------------------------------
  describe 'result shape' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.users (
            id bigint NOT NULL,
            email character varying NOT NULL,
            age integer
        );
      DDL
    end

    it 'returns a Hash' do
      expect(parse(content)).to be_a(Hash)
    end

    it 'sets adapter to static_parse' do
      expect(parse(content)[:adapter]).to eq('static_parse')
    end

    it 'marks the parse as inferred source' do
      expect(parse(content)[:source]).to eq(:static)
    end

    it 'includes a note about the parse source' do
      expect(parse(content)[:note]).to include('structure.sql')
    end

    it 'total_tables equals the number of tables parsed' do
      result = parse(content)
      expect(result[:total_tables]).to eq(result[:tables].size)
    end
  end

  # ---------------------------------------------------------------------------
  # Table parsing
  # ---------------------------------------------------------------------------
  describe 'table parsing' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
        CREATE TABLE public.posts (
            title character varying
        );
      DDL
    end

    it 'captures each CREATE TABLE as a table key (schema-qualifier stripped)' do
      expect(parse(content)[:tables].keys).to contain_exactly('users', 'posts')
    end

    it 'initialises each table with empty indexes and foreign_keys arrays' do
      result = parse(content)
      expect(result[:tables]['users'][:indexes]).to eq([])
      expect(result[:tables]['users'][:foreign_keys]).to eq([])
    end

    it 'handles IF NOT EXISTS and an unqualified, quoted table name' do
      content = %(CREATE TABLE IF NOT EXISTS "orders" (\n    id bigint\n);\n)
      expect(parse(content)[:tables]).to have_key('orders')
    end
  end

  # ---------------------------------------------------------------------------
  # Column parsing
  # ---------------------------------------------------------------------------
  describe 'column parsing' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.users (
            id bigint NOT NULL,
            email character varying(255) DEFAULT ''::character varying NOT NULL,
            created_at timestamp without time zone NOT NULL,
            "order" integer,
            active boolean
        );
      DDL
    end

    it 'captures column names, including quoted reserved words' do
      columns = parse(content)[:tables]['users'][:columns]
      expect(columns.pluck(:name)).to contain_exactly('id', 'email', 'created_at', 'order', 'active')
    end

    it 'strips NOT NULL to leave the bare type' do
      columns = parse(content)[:tables]['users'][:columns]
      expect(columns.find { |c| c[:name] == 'id' }[:type]).to eq('bigint')
    end

    it 'strips a DEFAULT clause (and trailing NOT NULL) to leave the bare type' do
      columns = parse(content)[:tables]['users'][:columns]
      expect(columns.find { |c| c[:name] == 'email' }[:type]).to eq('character varying(255)')
    end

    it 'preserves multi-word SQL types' do
      columns = parse(content)[:tables]['users'][:columns]
      expect(columns.find { |c| c[:name] == 'created_at' }[:type]).to eq('timestamp without time zone')
    end

    it 'does not capture columns outside a table block' do
      expect(parse("    email character varying\n")[:tables]).to be_empty
    end

    it 'skips table-level constraint lines' do
      content = <<~DDL
        CREATE TABLE public.users (
            id bigint NOT NULL,
            CONSTRAINT users_pkey PRIMARY KEY (id)
        );
      DDL
      names = parse(content)[:tables]['users'][:columns].pluck(:name)
      expect(names).to contain_exactly('id')
    end
  end

  # ---------------------------------------------------------------------------
  # Index parsing
  # ---------------------------------------------------------------------------
  describe 'index parsing' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
        CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);
        CREATE INDEX index_users_on_name_and_age ON public.users USING btree (name, age);
      DDL
    end

    it 'adds an index entry to the matching table' do
      expect(parse(content)[:tables]['users'][:indexes].size).to eq(2)
    end

    it 'records only the first column of each index (parity with schema.rb parser)' do
      indexes = parse(content)[:tables]['users'][:indexes]
      expect(indexes.pluck(:columns)).to contain_exactly('email', 'name')
    end

    it 'ignores CREATE INDEX for a table not in the schema' do
      content = "CREATE INDEX idx ON public.unknown USING btree (col);\n"
      expect(parse(content)[:tables]).to be_empty
    end

    it 'keeps an opclass-qualified column (drops the opclass)' do
      content = <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
        CREATE INDEX index_users_on_email ON public.users USING btree (email varchar_pattern_ops);
      DDL
      indexes = parse(content)[:tables]['users'][:indexes]
      expect(indexes.pluck(:columns)).to contain_exactly('email')
    end

    it 'skips a functional/expression index instead of mis-attributing the function name' do
      content = <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
        CREATE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));
      DDL
      expect(parse(content)[:tables]['users'][:indexes]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Internal table filtering
  # ---------------------------------------------------------------------------
  describe 'internal table filtering' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.ar_internal_metadata (
            key character varying NOT NULL
        );
        CREATE TABLE public.schema_migrations (
            version character varying NOT NULL
        );
        CREATE TABLE public.users (
            email character varying
        );
      DDL
    end

    it 'excludes ar_internal_metadata' do
      expect(parse(content)[:tables]).not_to have_key('ar_internal_metadata')
    end

    it 'excludes schema_migrations' do
      expect(parse(content)[:tables]).not_to have_key('schema_migrations')
    end

    it 'keeps application tables' do
      expect(parse(content)[:tables]).to have_key('users')
    end

    it 'does not leak columns from a skipped table into the next table' do
      expect(parse(content)[:tables]['users'][:columns].pluck(:name)).to contain_exactly('email')
    end
  end

  # ---------------------------------------------------------------------------
  # Config-driven exclusions
  # ---------------------------------------------------------------------------
  describe 'config-driven exclusions' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
        CREATE TABLE public.posts (
            title character varying
        );
        CREATE TABLE public.audit_logs (
            action character varying
        );
      DDL
    end

    after { config.excluded_tables.clear }

    it 'excludes a table listed in config.excluded_tables' do
      config.excluded_tables << 'users'
      expect(parse(content)[:tables]).not_to have_key('users')
    end

    it 'keeps tables not in the exclusion list' do
      config.excluded_tables << 'users'
      expect(parse(content)[:tables]).to have_key('posts')
    end

    it 'supports glob patterns in excluded_tables' do
      config.excluded_tables << 'audit_*'
      expect(parse(content)[:tables]).not_to have_key('audit_logs')
    end
  end

  # ---------------------------------------------------------------------------
  # Foreign key parsing (ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY)
  # ---------------------------------------------------------------------------
  describe 'foreign key parsing' do
    let(:content) do
      <<~DDL
        CREATE TABLE public.posts (
            id bigint NOT NULL,
            user_id bigint
        );
        CREATE TABLE public.users (
            id bigint NOT NULL
        );
        ALTER TABLE ONLY public.posts
            ADD CONSTRAINT fk_rails_abc123 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
      DDL
    end

    it 'attaches the foreign key to the altered table' do
      fks = parse(content)[:tables]['posts'][:foreign_keys]
      expect(fks.size).to eq(1)
    end

    it 'captures from_table, to_table, column and primary_key' do
      fk = parse(content)[:tables]['posts'][:foreign_keys].first
      expect(fk).to include(from_table: 'posts', to_table: 'users', column: 'user_id', primary_key: 'id')
    end

    it 'captures the ON DELETE referential action' do
      fk = parse(content)[:tables]['posts'][:foreign_keys].first
      expect(fk[:on_delete]).to eq('CASCADE')
    end

    it 'omits absent on_update rather than storing nil' do
      fk = parse(content)[:tables]['posts'][:foreign_keys].first
      expect(fk).not_to have_key(:on_update)
    end

    it 'ignores a FOREIGN KEY whose ALTER TABLE target is not a parsed table' do
      content = <<~DDL
        ALTER TABLE ONLY public.unknown
            ADD CONSTRAINT fk FOREIGN KEY (x_id) REFERENCES public.users(id);
      DDL
      expect(parse(content)[:tables]).to be_empty
    end

    it 'does not treat a non-foreign-key ADD CONSTRAINT as a foreign key' do
      content = <<~DDL
        CREATE TABLE public.users (
            id bigint NOT NULL
        );
        ALTER TABLE ONLY public.users
            ADD CONSTRAINT users_pkey PRIMARY KEY (id);
      DDL
      expect(parse(content)[:tables]['users'][:foreign_keys]).to be_empty
    end

    it 'captures ON UPDATE referential action' do
      content = <<~DDL
        CREATE TABLE public.posts (
            id bigint NOT NULL,
            user_id bigint
        );
        CREATE TABLE public.users (
            id bigint NOT NULL
        );
        ALTER TABLE ONLY public.posts
            ADD CONSTRAINT fk_rails_abc123 FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE SET NULL;
      DDL
      fk = parse(content)[:tables]['posts'][:foreign_keys].first
      expect(fk[:on_update]).to eq('SET NULL')
      expect(fk).not_to have_key(:on_delete)
    end

    it 'captures both ON DELETE and ON UPDATE' do
      content = <<~DDL
        CREATE TABLE public.posts (
            id bigint NOT NULL,
            user_id bigint
        );
        CREATE TABLE public.users (
            id bigint NOT NULL
        );
        ALTER TABLE ONLY public.posts
            ADD CONSTRAINT fk_rails_abc123 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE SET NULL;
      DDL
      fk = parse(content)[:tables]['posts'][:foreign_keys].first
      expect(fk[:on_delete]).to eq('CASCADE')
      expect(fk[:on_update]).to eq('SET NULL')
    end

    it 'handles composite foreign keys by keeping the first column' do
      content = <<~DDL
        CREATE TABLE public.tags (
            id bigint NOT NULL
        );
        CREATE TABLE public.taggings (
            id bigint NOT NULL,
            tag_id bigint,
            post_id bigint
        );
        ALTER TABLE ONLY public.taggings
            ADD CONSTRAINT fk_tagging FOREIGN KEY (tag_id, post_id) REFERENCES public.tags(id, post_id);
      DDL
      fk = parse(content)[:tables]['taggings'][:foreign_keys].first
      expect(fk[:column]).to eq('tag_id')
      expect(fk[:primary_key]).to eq('id')
    end
  end

  describe 'column type normalization edge cases' do
    it 'strips trailing NULL to leave the bare type' do
      content = "CREATE TABLE public.users (\n    email character varying NULL\n);\n"
      col = parse(content)[:tables]['users'][:columns].first
      expect(col[:type]).to eq('character varying')
    end

    it 'strips trailing comma from the last column' do
      content = "CREATE TABLE public.users (\n    email character varying,\n);\n"
      col = parse(content)[:tables]['users'][:columns].first
      expect(col[:type]).to eq('character varying')
    end

    it 'handles DEFAULT with complex expression' do
      content = "CREATE TABLE public.users (\n    status integer DEFAULT 1 NOT NULL\n);\n"
      col = parse(content)[:tables]['users'][:columns].first
      expect(col[:type]).to eq('integer')
    end
  end

  describe 'partition edge cases' do
    it 'handles a child with inline column list and PARTITION OF on same line as closing paren' do
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL
        )
        PARTITION BY RANGE (id);

        CREATE TABLE public.events_q1 (
            id bigint NOT NULL
        ) PARTITION OF public.events
        FOR VALUES FROM (1) TO (100);
      DDL

      child = parse(content)[:tables]['events_q1']
      expect(child[:partition_of]).to eq('events')
      expect(child[:columns].pluck(:name)).to include('id')
    end

    it 'handles a DEFAULT partition with trailing semicolon' do
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL
        )
        PARTITION BY RANGE (id);

        CREATE TABLE public.events_default PARTITION OF public.events DEFAULT;
      DDL

      child = parse(content)[:tables]['events_default']
      expect(child[:partition_bound]).to match(/\ADEFAULT\b/i)
    end

    it 'handles a partition child whose parent is excluded' do
      original_excluded = config.excluded_tables.dup
      config.excluded_tables << 'events'
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL
        )
        PARTITION BY RANGE (id);

        CREATE TABLE public.events_q1 PARTITION OF public.events
        FOR VALUES FROM (1) TO (100);
      DDL

      # Parent is excluded; child should still be parsed but with empty columns
      tables = parse(content)[:tables]
      expect(tables).to have_key('events_q1')
    ensure
      config.excluded_tables.replace(original_excluded)
    end
  end

  # ---------------------------------------------------------------------------
  # PostgreSQL declarative partitions (CREATE TABLE … PARTITION OF …)
  # ---------------------------------------------------------------------------
  describe 'partitioned table parsing' do
    after { config.excluded_tables.clear }

    let(:content) do
      <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL,
            created_at timestamp without time zone NOT NULL
        )
        PARTITION BY RANGE (created_at);

        CREATE TABLE public.events_2024 PARTITION OF public.events
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

        CREATE TABLE public.events_2025 PARTITION OF public.events
        FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
      DDL
    end

    it 'includes the parent table' do
      expect(parse(content)[:tables]).to have_key('events')
    end

    it 'expands PARTITION OF children as table entries' do
      expect(parse(content)[:tables].keys).to include('events_2024', 'events_2025')
    end

    it 'records the parent name on each child' do
      tables = parse(content)[:tables]
      expect(tables['events_2024'][:partition_of]).to eq('events')
      expect(tables['events_2025'][:partition_of]).to eq('events')
    end

    it 'does not mark the parent as a child of itself' do
      expect(parse(content)[:tables]['events']).not_to have_key(:partition_of)
    end

    it 'marks the parent as partitioned and captures the PARTITION BY method' do
      parent = parse(content)[:tables]['events']
      expect(parent[:partitioned]).to be(true)
      expect(parent[:partition_by]).to eq('RANGE (created_at)')
    end

    it 'records the FOR VALUES bound on each child' do
      bound = parse(content)[:tables]['events_2024'][:partition_bound]
      expect(bound).to include('FROM')
      expect(bound).to include('2024-01-01')
      expect(bound).to include('2025-01-01')
    end

    it 'copies parent columns onto children that have no column list (pg_dump form)' do
      columns = parse(content)[:tables]['events_2024'][:columns]
      expect(columns.pluck(:name)).to contain_exactly('id', 'created_at')
    end

    it 'counts parent and children in total_tables' do
      expect(parse(content)[:total_tables]).to eq(3)
    end

    it 'parses LIST and HASH bounds and a DEFAULT partition' do
      content = <<~DDL
        CREATE TABLE public.orders (
            id bigint NOT NULL,
            region character varying NOT NULL
        )
        PARTITION BY LIST (region);

        CREATE TABLE public.orders_us PARTITION OF public.orders
        FOR VALUES IN ('US');

        CREATE TABLE public.orders_0 PARTITION OF public.orders
        FOR VALUES WITH (MODULUS 4, REMAINDER 0);

        CREATE TABLE public.orders_default PARTITION OF public.orders
        DEFAULT;
      DDL

      tables = parse(content)[:tables]
      expect(tables.keys).to include('orders', 'orders_us', 'orders_0', 'orders_default')
      expect(tables['orders_us'][:partition_of]).to eq('orders')
      expect(tables['orders_us'][:partition_bound]).to include('IN')
      expect(tables['orders_0'][:partition_bound]).to include('MODULUS')
      expect(tables['orders_default'][:partition_bound]).to match(/\ADEFAULT\b/i)
    end

    it 'handles IF NOT EXISTS, quoting, and a schema qualifier on PARTITION OF' do
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint
        )
        PARTITION BY RANGE (id);

        CREATE TABLE IF NOT EXISTS public."events_q1" PARTITION OF public."events"
        FOR VALUES FROM (1) TO (100);
      DDL

      child = parse(content)[:tables]['events_q1']
      expect(child).to include(partition_of: 'events')
    end

    it 'parses a child that repeats its column list before PARTITION OF' do
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL,
            created_at timestamp without time zone NOT NULL
        )
        PARTITION BY RANGE (created_at);

        CREATE TABLE public.events_2024 (
            id bigint NOT NULL,
            created_at timestamp without time zone NOT NULL
        )
        PARTITION OF public.events
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
      DDL

      child = parse(content)[:tables]['events_2024']
      expect(child[:partition_of]).to eq('events')
      expect(child[:columns].pluck(:name)).to contain_exactly('id', 'created_at')
    end

    it 'attaches indexes declared on a partition child' do
      content = <<~DDL
        CREATE TABLE public.events (
            id bigint NOT NULL,
            created_at timestamp without time zone NOT NULL
        )
        PARTITION BY RANGE (created_at);

        CREATE TABLE public.events_2024 PARTITION OF public.events
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

        CREATE INDEX index_events_2024_on_created_at ON public.events_2024 USING btree (created_at);
      DDL

      indexes = parse(content)[:tables]['events_2024'][:indexes]
      expect(indexes.pluck(:columns)).to contain_exactly('created_at')
    end

    it 'skips a partition child listed in config.excluded_tables' do
      config.excluded_tables << 'events_2024'
      expect(parse(content)[:tables]).not_to have_key('events_2024')
      expect(parse(content)[:tables]).to have_key('events_2025')
    end

    it 'does not treat a regular CREATE TABLE as partitioned' do
      content = <<~DDL
        CREATE TABLE public.users (
            email character varying
        );
      DDL

      users = parse(content)[:tables]['users']
      expect(users).not_to have_key(:partitioned)
      expect(users).not_to have_key(:partition_of)
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling (introspector contract: never raise)
  # ---------------------------------------------------------------------------
  describe 'error handling' do
    it 'returns an error hash instead of raising on invalid-encoding input' do
      invalid = +"CREATE TABLE public.users (\n    email \xC3\x28 NOT NULL\n);\n"
      invalid.force_encoding('UTF-8')

      result = nil
      expect { result = parse(invalid) }.not_to raise_error
      expect(result[:error]).to include('db/structure.sql')
    end
  end
end
