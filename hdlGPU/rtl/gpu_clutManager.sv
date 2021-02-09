module gpu_clutManager (
	input			i_clk,
	input			i_rstGPU,
	
	input			i_issuePrimitive,			// (issuePrimitive != NO_ISSUE)
	input			i_CLUTIs8BPP,
	
	input			i_isPalettePrimitive,		//

	input			i_setClutLoading,			// loadClutPage

	input			i_incClutCount,
	output			o_stillRemainingClutPacket,
	
	input			i_endClutLoading,
	input			i_is4BitPalette,			// (GPU_REG_TexFormat == PIX_4BIT)
	
	input			i_rstTextureCache,
	input [14:0]	i_fifoDataOutClut,			// fifoDataOut[30:16];
	
	output [14:0]	o_adrClutCacheUpdate,
	output			o_isLoadingPalette,
	output [3:0]	o_currentClutBlock
);

// TODO : Check that weird i_rstTextureCache thing...

wire [15:0] newClutValue = { /*issue.*/i_rstTextureCache, i_fifoDataOutClut };

// Internal Register
reg [15:0]	RegCLUT;
reg   		rClutLoading;
reg	 [4:0]	rClutPacketCount;
reg         rPalette4Bit;
reg			lastBlockLoaded;
wire [4:0]	nextClutPacket	= rClutPacketCount + 5'd1;

wire endCondition = (rClutPacketCount == (i_CLUTIs8BPP ? 5'd15 : 5'd0));
always @(posedge i_clk)
begin
	if (i_rstGPU) begin
		RegCLUT						<= 16'h8000;	// Invalid CLUT ADR on reset.
		lastBlockLoaded				<= 0;
		rClutLoading				<= 1'b0;
		rClutPacketCount			<= 5'd0;
		rPalette4Bit				<= 1'b0;
	end else begin
		if (i_issuePrimitive) begin	// TODO OPTIMIZE : can not be same as 'i_setClutLoading' ?
			rClutPacketCount		<= 5'd0; // i_CLUTIs8BPP ? 5'd15 : 5'd1; // { i_CLUTIs8BPP , 3'b0, !i_CLUTIs8BPP }; // Load 1 packet or 16
			lastBlockLoaded			<= 0;
		end
		if (i_incClutCount) begin
			rClutPacketCount		<= nextClutPacket; // Increment+1
			lastBlockLoaded			<= endCondition;
		end
		if (i_setClutLoading) begin
			if (newClutValue[15] == 1'b0 && (newClutValue != RegCLUT)) begin
				// Loading only happens when :
				// - Switch from invalid to valid CLUT ADR. (Reset or cache flush)
				// - Switch from valid   do difference valid CLUT ADR.
				//
				// WARNING : rClutPacketCount the number of PACKET TO LOAD IS UPDATED WHEN LOADING THE TEXTURE FORMAT !!!! NOT WHEN CLUT FLAT IS SET !!!!
				//
				rClutLoading	<= 1'b1;
			end
			// Load always the value, whatever the value is (valid or invalid)
			RegCLUT		<= newClutValue;
		end
		if (i_endClutLoading) begin
			rClutLoading	<= 1'b0;
			rPalette4Bit	<= i_is4BitPalette;
		end
    end
end

wire [5:0]  XPosClut		= {1'b0, rClutPacketCount} + RegCLUT[5:0];
assign o_adrClutCacheUpdate	= { RegCLUT[14:6] , XPosClut };

assign o_isLoadingPalette   =  (rClutLoading & i_isPalettePrimitive) 
                            || (i_isPalettePrimitive & rPalette4Bit & i_CLUTIs8BPP);
assign o_stillRemainingClutPacket = !lastBlockLoaded;
assign o_currentClutBlock	= rClutPacketCount[3:0];
endmodule
