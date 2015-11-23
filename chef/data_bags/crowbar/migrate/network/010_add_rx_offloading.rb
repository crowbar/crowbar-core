def upgrade ta, td, a, d
  unless a.key? "enable_rx_offloading"
    a["enable_rx_offloading"] = a["enable_tx_offloading"] || ta["enable_rx_offloading"]
  end
  unless a.key? "enable_tx_offloading"
    a["enable_tx_offloading"] = ta["enable_tx_offloading"]
  end
  return a, d
end

def downgrade ta, td, a, d
  unless ta.key? "enable_tx_offloading"
    a.delete "enable_tx_offloading"
  end
  unless ta.key? "enable_rx_offloading"
    a.delete "enable_rx_offloading"
  end
  return a, d
end

