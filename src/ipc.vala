/********************************************************************
# Copyright 2014 Daniel 'grindhold' Brendle
#
# This file is part of Rainbow Lollipop.
#
# Rainbow Lollipop is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either
# version 3 of the License, or (at your option) any later
# version.
#
# Rainbow Lollipop is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with Rainbow Lollipop.
# If not, see http://www.gnu.org/licenses/.
*********************************************************************/

namespace RainbowLollipop {
    /**
     * Used to wrap all the data that is necessary to call a callback to a
     * successfully completed IPC call including the callback itself.
     * It is intended to be a universally applicable class but currently
     * it is only able to cover the needs_direct_input-usecase.
     * TODO: Modify this wrapper and the code in general to be able
     *       To store arbitrary callback / parameter combinations
     */
    class IPCCallbackWrapper {
        protected TrackWebView w;
        protected IPCCallback cb;
        protected Gee.ArrayList<GLib.Value?> args;

        /**
         * Construct a new IPC Callback wrapper
         */
        public IPCCallbackWrapper(TrackWebView web, IPCCallback cb, va_list al) {
            this.w = web;
            this.cb = cb;
            this.args = new Gee.ArrayList<GLib.Value?>();
            for (GLib.Value? v = al.arg<GLib.Value?>() ; v != null; v=al.arg<GLib.Value?>())
                this.args.add(v);
        }

        /**
         * Returns the WebView associated with this IPCCallbackWrapper
         * TODO: check if needed
         */
        /*public TrackWebView get_webview() {
           return this.w;
        }*/

        /**
         * Returns the callback function stored in this IPCCallbackWrapper
         * TODO: check if needed
         */
        /*public IPCCallback get_callback() {
            return this.cb;
        }*/

        /**
         * Returns the arguments stored along in this Callback
         * TODO: check if needed
         */
        /*public Gee.ArrayList<GLib.Value> get_args() {
            return this.args;
        }*/

        /**
         * Add arguments that come from the answer
         */
        public void add_arg(GLib.Value g) {
            this.args.add(g);
        }

        /**
         * Defines a default behaviour in case the call is not completed
         * within the defined timeout
         */
        public virtual void timeout(){}

        /**
         * Defines a default behaviour in case the call succeeds 
         */
        public virtual void execute(){}
    }

    class NeedsDirectInputCallback : IPCCallbackWrapper {
        public NeedsDirectInputCallback(TrackWebView web, IPCCallback cb, ...) {
            base(web,cb, va_list());
        }
        public override void timeout() {
            this.cb(this.args[0]);
        }

        public override void execute() {
            if (this.args.size == 2) {
                if (this.args[1].get_int() == 1) {
                    GLib.Idle.add(() => {
                        this.w.key_press_event(this.args[0] as Gdk.EventKey);
                        return false;
                    });
                } else {
                    GLib.Idle.add(() => {
                        this.cb(this.args[0] as Gdk.EventKey);
                        return false;
                    });
                }
            }
        }
    }   

    /**
     * A callback that is called when an IPC call has finished successfully
     */
    public delegate void IPCCallback(GLib.Value? v, ...);

    /**
     * The ZMQVent distributes ipc calls to each available WebExtension.
     * It is a Vent in the sense of the libzmq workload distributor design
     * pattern with a little exception. Along with each call goes the id
     * of a specific WebExtension and only this one Webextension will answer to
     * the call.
     */
    class ZMQVent {
        private static uint32 callcounter = 0;
        private static ZMQ.Context ctx;
        private static ZMQ.Socket sender;

        private static uint32 _current_sites = 0;
        public static uint32 current_sites {get{return ZMQVent._current_sites;}}

        /**
         * Setup the ZMQVent
         */
        public static void init() {
            ZMQVent.ctx = new ZMQ.Context();
            ZMQVent.sender = ZMQ.Socket.create(ctx, ZMQ.SocketType.PUSH);
            ZMQVent.sender.bind("tcp://127.0.0.1:"+Config.c.ipc_vent_port.to_string());
        }

        /**
         * Sends a request to a WebView if this webview directly needs the input
         * from the Keyboard
         */
        public static async void needs_direct_input(TrackWebView w,IPCCallback cb, Gdk.EventKey e) {
            uint64 page_id = w.get_page_id();
            //Create Callback
            uint32 callid = callcounter++;
            var cbw = new NeedsDirectInputCallback(w, cb, e);
            ZMQSink.register_callback(callid, cbw);
            string msgstring = IPCProtocol.NEEDS_DIRECT_INPUT+
                               IPCProtocol.SEPARATOR+
                               "%lld".printf(page_id)+
                               IPCProtocol.SEPARATOR+
                               "%ld".printf(callid);
            for (int i = 0; i < ZMQVent.current_sites; i++) {
                var msg = ZMQ.Msg.with_data(msgstring.data);
                msg.send(sender);
            }
        }

        /**
         * Issues a call to a webview that should return the current scroll position
         * TODO: implement
         */
        public static async long[] get_scroll_info(TrackWebView w, IPCCallback cb) {
            return {0,0};
        }

        /**
         * Increments the counter of the webextensions that have to be provided with messages
         */
        public static void register_site() {
            ZMQVent._current_sites++;
        }

        /**
         * Decrements the counter of webextensions
         */
        public static void unregister_site() {
            if (ZMQVent._current_sites > 0)
                ZMQVent._current_sites--;
        }
    }

    /**
     * Collects answers to IPC-Calls and causes the appropriate callbacks to be
     * executed.
     */
    class ZMQSink {
        private static Gee.HashMap<uint32, IPCCallbackWrapper> callbacks;
        private static ZMQ.Context ctx;
        private static ZMQ.Socket receiver;

        /**
         * Register a callback that is being mapped to a call id.
         * When an answer to the call with the given call id arrives, the callback will
         * be executed
         * Parallel to the callbacks registration a timeout will be scheduled.
         * If the sink does not receive any response in time, a default action will
         * be triggered and the callback will be forgotten
         */
        public static void register_callback(uint32 callid, IPCCallbackWrapper cbw) {
            ZMQSink.callbacks.set(callid, cbw);
            Timeout.add(500,()=>{
                IPCCallbackWrapper? _cbw = ZMQSink.callbacks.get(callid);
                if (_cbw != null) {
                    _cbw.timeout();
                    ZMQSink.callbacks.unset(callid);
                }
                return false;
            });
        }

        /**
         * Initializes the sink
         */
        public static void init() {
            ZMQSink.callbacks = new Gee.HashMap<uint32, IPCCallbackWrapper>();
            ZMQSink.ctx = new ZMQ.Context();
            ZMQSink.receiver = ZMQ.Socket.create(ctx, ZMQ.SocketType.PULL);
            ZMQSink.receiver.bind("tcp://127.0.0.1:"+Config.c.ipc_sink_port.to_string());
            try {
                new Thread<void*>.try(null,ZMQSink.run);
            } catch (GLib.Error e) {
                stdout.printf(_("Sink broke down\n"));
            }
        }

        /**
         * Thread-function to handle incoming responses
         */
        public static void* run() {
            while (true) {
                var input = ZMQ.Msg(); 
                input.recv(receiver);
                ZMQSink.handle_response((string)input.data);
            }
        }

        /**
         * Handles incoming responses and calls the stored callbacks accordingly
         */
        private static void handle_response(string input) {
            if (input.has_prefix(IPCProtocol.REGISTER)) {
                ZMQVent.register_site();
            }
            if (input.has_prefix(IPCProtocol.NEEDS_DIRECT_INPUT_RET)) {
                string[] splitted = input.split(IPCProtocol.SEPARATOR);
                int result = int.parse(splitted[2]);
                uint32 call_id = int.parse(splitted[3]);
                IPCCallbackWrapper? cbw = ZMQSink.callbacks.get(call_id);
                if (cbw == null) {
                    ZMQSink.callbacks.unset(call_id);
                    return;
                }
                var cbw_casted = cbw as NeedsDirectInputCallback;
                cbw_casted.add_arg(result);
                cbw_casted.execute();
                ZMQSink.callbacks.unset(call_id);
            }
            return;
        }

    }

    /**
     * Defines constant parts of the IPC Protocol
     */
    public class IPCProtocol : Object {
        public static const string NEEDS_DIRECT_INPUT = "ndi";
        public static const string NEEDS_DIRECT_INPUT_RET = "r_ndi";
        public static const string ERROR = "error";
        public static const string REGISTER = "reg";
        public static const string SEPARATOR = "-";
    }
}
