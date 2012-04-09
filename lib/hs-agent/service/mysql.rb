require 'mysql'

module HSAgent
  class Service::Mysql < Service
    @supported_services = [:Mysql]

    def self.connect(where)
      ::Mysql.connect where[:hostname], where[:username], where[:password], where[:database], where[:port]
    end

    def self.exec_interpolated(conn, sql, values)
      values = values.map do |v| conn.escape_string(v) end
      $logger.debug sql % values
      conn.query sql % values
    end

    # id             => unique id identifying the particular service instance
    # service        => service type (postgresql, memcached, etc)
    # connectiondata => credentials: :port, :hostname, :username, :password, :database

    def self.update(id, service, connectiondata, old_connectiondata)
      conn = connect $config[:service_mysql_dsn]
      # Create/Update the user
      res = exec_interpolated conn, "SELECT 1 FROM mysql.user where user='%s'", [connectiondata[:username]]
      values = [connectiondata[:username], connectiondata[:password]]
      if res.num_rows == 0
        exec_interpolated conn, "CREATE USER '%s'@'%%' IDENTIFIED BY '%s'", values
      else
        exec_interpolated conn, "SET PASSWORD FOR '%s'@'%%' = PASSWORD('%s')", values
      end

      # Create/Update the database
      res = exec_interpolated conn, "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='%s'", [connectiondata[:database]]
      if res.num_rows == 0
        sql = "CREATE DATABASE %s" # no '' here
        exec_interpolated conn, sql, [connectiondata[:database]]
      end

      values = [connectiondata[:database], connectiondata[:username]]
      exec_interpolated conn, "GRANT ALL PRIVILEGES ON %s.* TO '%s'@'%%'", values
    end
    def self.delete(id, service, connectiondata)
      conn = connect $config[:service_mysql_dsn]

      exec_interpolated conn, "DROP DATABASE IF EXISTS %s", [connectiondata[:database]]

      res = exec_interpolated conn, "SELECT 1 FROM mysql.user WHERE user='%s'", [connectiondata[:username]]
      if res.num_rows > 0
        exec_interpolated conn, "DROP USER '%s'@'%%'", [connectiondata[:username]]
      end
    end

    def self.lock_writes(id, service, connectiondata)
      conn = connect $config[:service_mysql_dsn]

      exec_interpolated conn, "REVOKE INSERT, UPDATE, CREATE ON %s.* FROM '%s'@'%%'", [connectiondata[:database], connectiondata[:username]]
    end
  end
end
