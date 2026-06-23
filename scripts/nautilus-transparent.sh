#!/bin/bash
# Make Nautilus transparent

mkdir -p ~/.config/gtk-4.0 ~/.config/gtk-3.0

cat > ~/.config/gtk-4.0/gtk.css << 'EOF'
/* Nautilus transparency */
.nautilus-window,
.nautilus-window scrolledwindow,
.nautilus-window paned,
.nautilus-window > widget > box {
  background-color: rgba(0, 0, 0, 0.85);
}

.nautilus-window notebook {
  background-color: transparent;
}
EOF

cat > ~/.config/gtk-3.0/gtk.css << 'EOF'
/* Nautilus transparency */
.nautilus-window.background {
  background-color: rgba(0, 0, 0, 0.85);
}

.nautilus-window notebook {
  background-color: transparent;
}
EOF

echo "Nautilus transparency configured. Restart Nautilus to apply."
