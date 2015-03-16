namespace RainbowLollipop {
    class SearchWidget : Clutter.Actor {
        private Gtk.Entry entry;
        private Gtk.Button next;
        private Gtk.Button prev;
        private Gtk.Button close;

        private GtkClutter.Actor a_entry;
        private GtkClutter.Actor a_next;
        private GtkClutter.Actor a_prev;
        private GtkClutter.Actor a_close; 
        
        private Clutter.BoxLayout line_box_layout;

        private WebKit.FindController find_controller;

        public SearchWidget(Clutter.Actor webactor, WebKit.FindController fc) {
            this.find_controller = fc;
            this.next = new Gtk.Button.from_icon_name("go-down", Gtk.IconSize.MENU);
            this.prev = new Gtk.Button.from_icon_name("go-up", Gtk.IconSize.MENU);
            this.close = new Gtk.Button.from_icon_name("window-close", Gtk.IconSize.MENU);
            this.entry = new Gtk.Entry();

            this.a_next = new GtkClutter.Actor.with_contents(this.next);
            this.a_prev = new GtkClutter.Actor.with_contents(this.prev);
            this.a_entry = new GtkClutter.Actor.with_contents(this.entry);
            this.a_close = new GtkClutter.Actor.with_contents(this.close);

            var np_box = new Clutter.Actor();
            np_box.width = 40;
            np_box.height = 80;
            var np_box_layout = new Clutter.BoxLayout();
            np_box_layout.orientation = Clutter.Orientation.VERTICAL;
            np_box.set_layout_manager(np_box_layout);
            this.line_box_layout = new Clutter.BoxLayout();
            this.line_box_layout.orientation = Clutter.Orientation.HORIZONTAL;
            this.set_layout_manager(this.line_box_layout);

            np_box.add_child(this.a_prev);
            np_box.add_child(this.a_next);
            this.add_child(np_box);
            this.add_child(this.a_entry);
            this.add_child(this.a_close);

            this.background_color = Clutter.Color.from_string(Config.c.colorscheme.empty_track);
            this.height =  100;
            this.add_constraint(
                new Clutter.BindConstraint(webactor, Clutter.BindCoordinate.WIDTH, 0)
            );
            this.add_constraint(
                new Clutter.AlignConstraint(webactor, Clutter.AlignAxis.Y_AXIS, 0.8f)
            );
            this.opacity = 0xAA;
        }
    }
}
