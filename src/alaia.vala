using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using WebKit;
using Gee;


namespace alaia {

    enum AppState {
        NORMAL,
        TRACKLIST
    }

    class ZMQVent() {
        private static const string VENT = "tcp://127.0.0.1:26010";

        private uint32 callcounter = 0;
        private ZMQContext ctx;
        private ZMQSocket sender;

        public ZMQVent() {
            this.ctx = new ZMQ.Context(1);
            this.sender = ZMQ.Socket.create(ctx)
            this.sender.bind(ZMQVent.VENT);
        }

        public async needs_direct_input(uint64 page_id) {
            
        }
    }

    class ZMQSink() {
        private static const string SINK = "tcp://127.0.0.1:26011";

        private Gee.HashMap<uint32, ZMQCallback> callbacks;
        private ZMQContext ctx;
        private ZMQ.Socket receiver;

        public ZMQSink() {
            this.callbacks = new Gee.HashMap<uint32, ZMQCallback>(
            this.ctx = new ZMQ.Context(1);
            this.receiver = ZMQ.Socket.create(ctx);
            this.receiver.bind(ZMQSink.SINK);
        }
    }

    public class TrackWebView : WebKit.WebView {
        public HistoryTrack track{ get;set; }

        public TrackWebView() {
        }

        public bool needs_direct_input() {
            if (messenger != null) {
                try {
                    return messenger.needs_direct_input();
                } catch (IOError e) {
                    warning("Error here"+e.message);
                    return false;
                }
            }
            warning("Could not reach rendering engine via dbus");
            return false;
        }
    }

    class ContextMenu : Gtk.Menu {
        private Gtk.ImageMenuItem new_track_from_node;
        private Gtk.ImageMenuItem delete_branch;
        private Gtk.ImageMenuItem copy_url;
        private Gtk.ImageMenuItem delete_track;
        private Gtk.ImageMenuItem open_folder;
        private Gtk.ImageMenuItem open_download;
        private Node? node;
        private Track? track;
        
        public ContextMenu () {
            //Nodes
            this.new_track_from_node = new Gtk.ImageMenuItem.with_label("New Track from Branch");
            this.new_track_from_node.set_image(
                new Gtk.Image.from_icon_name("go-jump", Gtk.IconSize.MENU)
            );
            this.new_track_from_node.activate.connect(do_new_track_from_node);
            this.add(this.new_track_from_node);
            this.delete_branch = new Gtk.ImageMenuItem.with_label("Close Branch");
            this.delete_branch.set_image(
                new Gtk.Image.from_icon_name("edit-delete", Gtk.IconSize.MENU)
            );
            this.delete_branch.activate.connect(do_delete_branch);
            this.add(this.delete_branch);

            //Sitenodes
            this.copy_url = new Gtk.ImageMenuItem.with_label("Copy URL");
            this.copy_url.set_image(
                new Gtk.Image.from_icon_name("edit-copy", Gtk.IconSize.MENU)
            );
            this.copy_url.activate.connect(do_copy_url);
            this.add(this.copy_url);


            //DownloadNodes
            this.open_folder = new Gtk.ImageMenuItem.with_label("Open folder");
            this.open_folder.set_image(
                new Gtk.Image.from_icon_name("folder", Gtk.IconSize.MENU)
            );
            this.open_folder.activate.connect(do_open_folder);
            this.add(this.open_folder);
            this.open_download = new Gtk.ImageMenuItem.with_label("Open");
            this.open_download.set_image(
                new Gtk.Image.from_icon_name("document-open", Gtk.IconSize.MENU)
            );
            this.open_download.activate.connect(do_open_download);
            this.add(this.open_download);

            //Track
            this.add(new Gtk.SeparatorMenuItem());
            this.delete_track = new Gtk.ImageMenuItem.with_label("Close Track");
            this.delete_track.set_image(
                new Gtk.Image.from_icon_name("window-close", Gtk.IconSize.MENU)
            );
            this.delete_track.activate.connect(do_delete_track);
            this.add(this.delete_track);

            this.show_all();
        }

        public void set_context(Track? track, Node? node) {
            this.track = track;
            this.node = node;
            
            this.delete_track.visible = this.track != null;
            this.new_track_from_node.visible = this.node != null;
            this.copy_url.visible = this.node != null && this.node is SiteNode;
            this.open_folder.visible = this.node != null && this.node is DownloadNode;
            this.open_download.visible = this.node != null && this.node is DownloadNode &&
                                         (this.node as DownloadNode).is_finished();
            this.delete_branch.visible = this.node != null;
        }

        public void do_new_track_from_node(Gtk.MenuItem m) {
            if (this.node != null)
                this.node.move_to_new_track();
        }
        public void do_delete_branch(Gtk.MenuItem m) {
            if (this.node  != null)
                this.node.delete_node();
        }
        public void do_copy_url(Gtk.MenuItem m) {
            if (this.node != null && this.node is SiteNode){
                var c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
                c.set_text((this.node as SiteNode).url,-1);
            }
        }
        public void do_delete_track(Gtk.MenuItem m) {
            if (this.track != null)
                this.track.delete_track();
        }
        public void do_open_folder(Gtk.MenuItem m) {
            if (this.node is DownloadNode)
                (this.node as DownloadNode).open_folder();
        }
        public void do_open_download(Gtk.MenuItem m) {
            if (this.node is DownloadNode)
                (this.node as DownloadNode).open_download();
        }
    }

    class Application : Gtk.Application {
        private static Application app;

        private GtkClutter.Window win;
        private ContextMenu _context;
        public ContextMenu context {get{return _context;}}
        private Gee.HashMap<HistoryTrack,WebKit.WebView> webviews;
        private Gtk.Notebook webviews_container;
        private GtkClutter.Actor webact;

        public TrackList tracklist {get;set;}
        private TrackListBackground tracklist_background;
        
        private AppState _state;

        public AppState state {
            get {
                return this._state;
            }
        }

        private Application()  {
            GLib.Object(
                application_id : "de.grindhold.alaia",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE,
                register_session : true
            );

            //Load config

            Config.load();
            
            this._state = AppState.TRACKLIST;

            this.webviews = new Gee.HashMap<HistoryTrack, TrackWebView>();
            this.webviews_container = new Gtk.Notebook();
            this.webviews_container.show_tabs = false;
            this.webact = new GtkClutter.Actor.with_contents(this.webviews_container);

            this.win = new GtkClutter.Window();
            this.win.set_title("alaia");
            this.win.maximize();
            this.win.icon_name="alaia";
            this.win.key_press_event.connect(do_key_press_event);
            this.win.destroy.connect(do_delete);

            this._context = new ContextMenu();

            var stage = this.win.get_stage();
            this.webact.add_constraint(new Clutter.BindConstraint(
                stage, Clutter.BindCoordinate.SIZE, 0)
            );
            stage.add_child(this.webact);
            stage.reactive = true;

            this.tracklist_background = new TrackListBackground(stage);
            stage.add_child(this.tracklist_background);

            this.tracklist = (TrackList)this.tracklist_background.get_first_child();
            this.win.show_all();
            this.tracklist_background.emerge();
        }

        //TODO: exchange Gtk.Action for GLib.Simpleaction as soon as webkitgtk is ready for it
        public bool do_web_context_menu(WebKit.ContextMenu cm, Gdk.Event e, WebKit.HitTestResult htr){
            var w = this.webviews_container.get_nth_page(this.webviews_container.page) as WebView;
            WebKit.ContextMenuItem mi;
            //GLib.SimpleAction a;
            Gtk.Action a;
            cm.remove_all();
            if (w.can_go_back()) {
                //a = new GLib.SimpleAction("navigate-back",null);
                a = new Gtk.Action("nanvigate-back", "Go Back", null, null);
                a.activate.connect(()=>{
                    this.tracklist.current_track.go_back();
                });
                cm.append(new WebKit.ContextMenuItem(a as Gtk.Action));
            }
            if (w.can_go_forward()) {
                //a = new GLib.SimpleAction("navigate-forward",null);
                a = new Gtk.Action("nanvigate-forward", "Go Forward", null, null);
                a.activate.connect(()=>{
                    this.tracklist.current_track.go_forward();
                });
                cm.append(new WebKit.ContextMenuItem(a as Gtk.Action));
            }
            return false;
        }

        public WebKit.WebView get_web_view(HistoryTrack t) {
            if (!this.webviews.has_key(t)) {
                var w = new TrackWebView();
                w.track = t;
                w.context_menu.connect(do_web_context_menu);
                w.get_context().download_started.connect(t.log_download);
                this.webviews.set(t,w);
                this.webviews_container.append_page(w);
            }
            return this.webviews.get(t);
        }

        public void destroy_web_view(HistoryTrack t) {
            if (this.webviews.has_key(t))
                this.webviews[t].destroy();
        }
    
        public void show_web_view(HistoryTrack t) {
            if (this.webviews.has_key(t)){
                var page = this.webviews_container.page_num(this.webviews[t]);
                this.webviews_container.set_current_page(page);
                this.webviews_container.show_all();
            }
        }
        
        public void do_delete() {
            Gtk.main_quit();
        }

        public void show_tracklist() {
            this.tracklist_background.emerge();
            this._state = AppState.TRACKLIST;
        }
        public void hide_tracklist() {
            this.tracklist_background.disappear();
            this._state = AppState.NORMAL;
        }
        
        public void do_needs_direct_input(bool ndi) {
        }

        public bool do_key_press_event(Gdk.EventKey e) {
            var t = this.tracklist.current_track;
            if (t != null) {
                if((this.get_web_view(t) as TrackWebView).needs_direct_input() )
                    return false;
            }
            switch (this._state) {
                case AppState.NORMAL:
                    switch (e.keyval) {
                        case Gdk.Key.Tab:
                            this.show_tracklist();
                            return true;
                        default:
                            return false;
                    }
                case AppState.TRACKLIST:
                    switch (e.keyval) {
                        case Gdk.Key.Tab:
                            this.hide_tracklist();
                            return true;
                        default:
                            return false;
                    }
            }
            return false;
        }

        public static Application S() {
            return Application.app;
        }
        
        public static int main(string[] args) {
            if (GtkClutter.init(ref args) != Clutter.InitError.SUCCESS){
                stdout.printf("Could not initialize GtkClutter");
            }
            Application.app = new Application();
            WebKit.WebContext.get_default().set_process_model(
                WebKit.ProcessModel.MULTIPLE_SECONDARY_PROCESSES
            );
            WebKit.WebContext.get_default().set_favicon_database_directory("/tmp/alaia_favicons");
            stdout.printf(get_data_filename("wpe")+"\n");
            WebKit.WebContext.get_default().set_web_extensions_directory(get_data_filename("alaia/wpe"));
            Gtk.main();
            return 0;
        }

        public static string get_config_filename(string name) {
            File f = File.new_for_path(GLib.Environment.get_user_config_dir()+Config.C+name);
            if (f.query_exists())
                return f.get_path();
            foreach (string dir in GLib.Environment.get_system_config_dirs()) {
                f = File.new_for_path(dir+Config.C+name);
                if (f.query_exists())
                    return f.get_path();
            }
            f = File.new_for_path("/etc"+Config.C+name);
            if (f.query_exists())
                return f.get_path();
#if DEBUG
            return "cfg/"+name;
#else
            return "";
#endif
        }

        public static string get_data_filename(string name) {
            File f = File.new_for_path(GLib.Environment.get_user_data_dir()+Config.C+name);
            if (f.query_exists())
                return f.get_path();
            foreach (string dir in GLib.Environment.get_system_data_dirs()) {
                f = File.new_for_path(dir+Config.C+name);
                if (f.query_exists())
                    return f.get_path();
            }
#if DEBUG
            return "data/"+name;
#else
            return "";
#endif
        }
    }
}
