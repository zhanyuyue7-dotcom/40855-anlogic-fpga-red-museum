// Integration contract reference (not auto-included in the old top).
// Rename these nets to the latest project's UDP and frame allocator interfaces.
// These are REQUIRED connections, not safe tie-off defaults.
//
// hxfp_receiver #(.TIMEOUT_CYCLES(1500000000)) image_rx (
//   .clk(image_domain_clk), .rst(image_domain_reset),
//   .rx_ready(udp_image_accept_new_datagram),
//   .rx_start(udp_image_payload_start), .rx_valid(udp_image_payload_valid),
//   .rx_data(udp_image_payload_byte), .rx_end(udp_image_payload_end),
//   .rx_peer({udp_image_source_ip,udp_image_source_port}),
//   .tx_valid(udp_image_ack_valid), .tx_ready(udp_image_ack_ready),
//   .tx_data(udp_image_ack_byte), .tx_last(udp_image_ack_last),
//   .tx_peer(udp_image_reply_destination),
//   .frame_begin(allocator_reserve_request),
//   .frame_begin_ready(allocator_offscreen_buffer_reserved),
//   .pixel_valid(network_pixel_valid), .pixel_ready(writer_fifo_has_space),
//   .pixel_address(network_pixel_index), .pixel_rgb565(network_rgb565),
//   .frame_commit(network_frame_commit_request),
//   .frame_commit_ready(memory_drained_and_frame_boundary_commit_complete),
//   .frame_abort(discard_staging_buffer), .frame_error(storage_failure),
//   .transfer_active(network_owns_write_buffer), .received_bytes(network_received),
//   .displayed_frames(network_committed_frames)
// );
// hxfp_rgb565_expand expand(.rgb565(network_rgb565),.rgb888_word(network_rgb888));
