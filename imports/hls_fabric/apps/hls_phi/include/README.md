# Phi source headers

`phi_protocol.hrl` defines this application's messages. The `*_impl.hrl` files share actor behavior between line and halo wrappers; `phi_neighborhood.hrl` selects bounded geometry. Actors include these through the `hls_phi` application so dynamic compilation and installed source builds use the same files. These are example contracts, not compiler or transport headers.
