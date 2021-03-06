module Specjour
  class Worker
    include Protocol
    include SocketHelpers
    attr_accessor :printer_uri
    attr_reader :project_path, :specs_to_run, :number, :batch_size

    def initialize(project_path, printer_uri, number, batch_size)
      @project_path = project_path
      @specs_to_run = specs_to_run
      @number = number.to_i
      @batch_size = batch_size.to_i
      self.printer_uri = printer_uri
      GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=)
      DistributedFormatter.batch_size = batch_size
      set_env_variables
    end

    def printer_uri=(val)
      @printer_uri = URI.parse(val)
    end

    def run
      printer.send_message(:ready)
      run_time = 0
      Dir.chdir(project_path)
      while !printer.closed? && data = printer.gets(TERMINATOR)
        spec = load_object(data)
        if spec
          run_time += Benchmark.realtime do
            run_spec spec
          end
          printer.send_message(:ready)
        else
          printer.send_message(:done)
          printer.send_message(:worker_summary=, {:duration => sprintf("%6f", run_time)})
          printer.close
        end
      end
    end

    protected

    def printer
      @printer ||= printer_connection
    end

    def printer_connection
      Connection.new printer_uri
    end

    def run_spec(spec)
      puts "Running #{spec}"
      options = Spec::Runner::OptionParser.parse(
        ['--format=Specjour::DistributedFormatter', spec],
        $stderr,
        printer_connection
      )
      Spec::Runner.use options
      options.run_examples
    end

    def set_env_variables
      ENV['PREPARE_DB'] = 'true'
      ENV['RSPEC_COLOR'] = 'true'
      if number > 1
        ENV['TEST_ENV_NUMBER'] = number.to_s
      else
        ENV['TEST_ENV_NUMBER'] = nil
      end
    end
  end
end
