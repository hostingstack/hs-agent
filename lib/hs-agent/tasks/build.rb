# -*- mode: ruby -*-
desc "Build binary distribution"
task :build do
  require 'jruby/jrubyc'
  jruby = ENV['JRUBY_BIN'] || `which hsjruby`.chomp
  if jruby.nil? or jruby.empty?
    raise "Cannot find hsjruby in PATH"
  end
  puts "Using hsjruby in #{jruby} for shebangs."

  builddir = ENV['EFC_PRODUCT_BUILDDIR'] || "../#{`basename $PWD`.chomp}-build/"
  FileUtils.rm_rf builddir
  FileUtils.mkdir builddir
  FileUtils.mkdir builddir + "/bin"
  FileUtils.mkdir builddir + "/lib"
  FileUtils.cp "Rakefile", builddir
  FileUtils.cp "Gemfile", builddir
  FileUtils.cp "Gemfile.lock", builddir
  FileUtils.cp_r "gems", builddir
  FileUtils.cp_r "config", builddir

  # modify bins to use jruby to start
  BIN_FILES.each do |fn|
    File.open(builddir+"/bin/#{fn}", "w") do |f|
      f.puts "#!#{jruby}"
      f.write File.read("bin/#{fn}")
    end
    File.chmod 0755, builddir+"/bin/#{fn}"
  end

  def compile(dir, target)
    errors = JRuby::Compiler.
      compile_files_with_options(dir,
                                 :basedir => Dir.pwd,
                                 :prefix => JRuby::Compiler::DEFAULT_PREFIX,
                                 :target => target,
                                 :java => false,
                                 :javac => false,
                                 :javac_options => nil,
                                 :classpath => nil,
                                 :handles => false,
                                 :verbose => true
                                 )
    if errors != 0
      raise "JRuby compiler failed with #{errors} errors when compiling #{dir.inspect}."
    end
  end
  compile "lib", builddir
  compile "gems/hs-api/lib", builddir
  Dir.glob(builddir + "/gems/hs-api/lib/**/*.rb").each do |fn|
    File.unlink fn
  end
  FileUtils.rm_rf builddir+"/gems/hs-api/.git"
end

