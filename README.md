HSAgent
=======

This agent does a lot of things, therefore it is split into "roles".
Each role defines which threads are to be run (usually these are for
periodic tasks), which code gets run on startup, and so on.

Multiple roles can be loaded together in a single agent instance.

As the agent also acts on Resque jobs, the agent is split into two
process types (the $mode):
  * main
  * worker

Both can be combined into a single process ($mode == both), but this
is not recommended for production setups. It is expected that in
production multiple worker processes will be used.

The main process exposes a Thrift server. The worker processes call
- if needed - into the main process (using the Thrift server). This
is usually only necessary for the AppHost role, where the worker
processes would need to modify Scheduler state.

For the Gateway role, the Thrift server is also used by the external
SshGateway process/service. There's also an additional TCP interface
for the HttpGateway service, this is implemented using EventMachine.

