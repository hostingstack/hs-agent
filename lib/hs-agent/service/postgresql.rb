module HSAgent
  class Service::Postgresql < Service
    @supported_services = [:Postgresql]
    
    def self.exec_interpolated(conn, sql, values)
      values = values.map do |v| conn.escape_string(v) end
      conn.exec sql % values
    end
    
    def self.connect(opts)
      opts = opts.map do |k,v| "#{k.to_s}='#{v}'" end
      PGconn.open opts.join(' ')
    end
    
    # id             => unique id identifying the particular service instance
    # service        => service type (postgresql, memcached, etc)
    # connectiondata => credentials: :port, :hostname, :username, :password, :database
    
    def self.update(id, service, connectiondata, old_connectiondata)
      conn = connect $config[:service_pg_dsn]
      
      # Create/Update the user
      res = conn.exec "SELECT 1 FROM pg_roles WHERE rolname=$1", [connectiondata[:username]]
      if res.num_tuples == 0
        method = 'CREATE'
      else
        method = 'ALTER'
      end
      
      values = [connectiondata[:username], connectiondata[:password]]
      exec_interpolated conn, "#{method} USER %s ENCRYPTED PASSWORD '%s'", values
      
      # Create/Update the database
      res = conn.exec "SELECT 1 FROM pg_database WHERE datname=$1", [connectiondata[:database]]
      if res.num_tuples == 0
        sql = "CREATE DATABASE %s OWNER %s ENCODING '%s' LC_COLLATE '%s' LC_CTYPE '%s' TEMPLATE template0"
        encoding = 'utf8'
        collation = 'en_US.UTF-8'
        ctype = 'en_US.UTF-8'
        
        values = [connectiondata[:database], connectiondata[:username], encoding, collation, ctype]
        exec_interpolated conn, sql, values
      else
        # Postgres doesn't allow encoding/collations to be changed on existing databases
        values = [connectiondata[:database], connectiondata[:username]]
        exec_interpolated conn, 'ALTER DATABASE %s OWNER TO %s', values
      end
      
      # Revoke all database-level (especially CONNECT) permissions for everybody. This excludes superusers and
      # the owner of the database.
      exec_interpolated conn, 'REVOKE ALL ON DATABASE %s from public', [connectiondata[:database]]
      
    end
    
    def self.delete(id, service, connectiondata)
      conn = connect $config[:service_pg_dsn]
      
      res = conn.exec "SELECT 1 FROM pg_roles WHERE rolname=$1", [connectiondata[:username]]
      
      # First, remove LOGIN-capabilities for the user to delete and kill all active connections
      if res.num_tuples > 0
        exec_interpolated conn, "ALTER ROLE %s NOLOGIN", [connectiondata[:username]]
        conn.exec "SELECT pg_terminate_backend(procpid) FROM pg_stat_activity WHERE usename=$1", [connectiondata[:username]]
      end
      
      # Databases can only be dropped when no users are connected
      exec_interpolated conn, "DROP DATABASE IF EXISTS %s", [connectiondata[:database]]
      
      # Roles can only be dropped when no objects reference to them (ownership et al)
      exec_interpolated conn, "DROP ROLE IF EXISTS %s", [connectiondata[:username]]
    end
    
    
    # FIXME: This requires PG 9.0, only handles relations in the public schema and
    # won't prevent the user from GRANTing himself these permissions again.
    def self.lock_writes(id, service, connectiondata)
      dsn = $config[:service_pg_dsn]
      dsn[:dbname] = connectiondata[:database]
      conn = connect dsn
      conn.transaction do |conn|
        exec_interpolated conn, "REVOKE INSERT, UPDATE ON ALL TABLES IN SCHEMA public FROM %s", [connectiondata[:username]]
      end
    end
  end
end
