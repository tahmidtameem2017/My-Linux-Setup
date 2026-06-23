#!/bin/bash
# Make all GTK windows transparent system-wide

mkdir -p ~/.config/gtk-4.0 ~/.config/gtk-3.0

cat > ~/.config/gtk-4.0/gtk.css << 'EOF'
/* System-wide window transparency */
window,
window.background,
window > box,
window > widget > box,
window scrolledwindow,
window paned {
  background-color: rgba(0, 0, 0, 0.85);
}

/* Exclude buttons and interactive elements */
button,
entry,
frame,
list,
row {
  background-color: rgba(30, 30, 30, 0.95);
}
EOF

cat > ~/.config/gtk-3.0/gtk.css << 'EOF'
/* System-wide window transparency */
window.background {
  background-color: rgba(0, 0, 0, 0.85);
}

/* Exclude buttons and interactive elements */
button,
entry,
frame,
list,
row {
  background-color: rgba(30, 30, 30, 0.95);
}
EOF

echo "System-wide transparency configured. Restart applications to apply."
