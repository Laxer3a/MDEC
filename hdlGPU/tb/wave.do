onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /a_gpu_tb/i_nrst
add wave -noupdate /a_gpu_tb/clk
add wave -noupdate /a_gpu_tb/gpu_inst/rstGPU
add wave -noupdate -divider {New Divider}
add wave -noupdate -expand -subitemconfig {/a_gpu_tb/gpu_inst/issue.storeCommand {-color Gold -height 15}} /a_gpu_tb/gpu_inst/issue
add wave -noupdate /a_gpu_tb/gpu_inst/issue.storeCommand
add wave -noupdate /a_gpu_tb/gpu_inst/Fifo_instLSB/rd_data_o
add wave -noupdate /a_gpu_tb/gpu_inst/Fifo_instMSB/rd_data_o
add wave -noupdate /a_gpu_tb/gpu_inst/currState
add wave -noupdate /a_gpu_tb/gpu_inst/bIgnoreColor
add wave -noupdate /a_gpu_tb/gpu_inst/bIsPerVtxCol
add wave -noupdate /a_gpu_tb/gpu_inst/command
add wave -noupdate /a_gpu_tb/gpu_inst/bIsPolyOrRect
add wave -noupdate /a_gpu_tb/gpu_inst/bIsPolyCommand
add wave -noupdate /a_gpu_tb/gpu_inst/bIsRectCommand
add wave -noupdate /a_gpu_tb/gpu_inst/canIssueWork
add wave -noupdate /a_gpu_tb/gpu_inst/canRead
add wave -noupdate /a_gpu_tb/gpu_inst/currWorkState
add wave -noupdate /a_gpu_tb/gpu_inst/pixelX
add wave -noupdate /a_gpu_tb/gpu_inst/pixelY
add wave -noupdate /a_gpu_tb/gpu_inst/RegCommand
add wave -noupdate /a_gpu_tb/gpu_inst/selNextX
add wave -noupdate /a_gpu_tb/gpu_inst/selNextY
add wave -noupdate /a_gpu_tb/gpu_inst/isBottomInside
add wave -noupdate /a_gpu_tb/gpu_inst/isBottomInsideBBox
add wave -noupdate /a_gpu_tb/gpu_inst/isCCWInsideL
add wave -noupdate /a_gpu_tb/gpu_inst/isCCWInsideR
add wave -noupdate /a_gpu_tb/gpu_inst/isCWInsideL
add wave -noupdate /a_gpu_tb/gpu_inst/isCWInsideR
add wave -noupdate /a_gpu_tb/gpu_inst/stencilReadAdr
add wave -noupdate /a_gpu_tb/gpu_inst/stencilReadSig
add wave -noupdate /a_gpu_tb/gpu_inst/stencilReadValue
add wave -noupdate /a_gpu_tb/gpu_inst/swap
add wave -noupdate /a_gpu_tb/gpu_inst/stepY
add wave -noupdate /a_gpu_tb/gpu_inst/validL
add wave -noupdate /a_gpu_tb/gpu_inst/validR
add wave -noupdate /a_gpu_tb/gpu_inst/isValidPixelL
add wave -noupdate /a_gpu_tb/gpu_inst/isValidPixelR
add wave -noupdate /a_gpu_tb/gpu_inst/enteredTriangle
add wave -noupdate /a_gpu_tb/gpu_inst/requestNextPixel
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {5871 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 202
configure wave -valuecolwidth 161
configure wave -justifyvalue left
configure wave -signalnamewidth 2
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {2561 ps} {9117 ps}
