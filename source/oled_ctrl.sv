`timescale 1ns / 1ps

module oled_ctrl (
  // System Ports
  input sysClkIn,
  input sysRstIn,

  // Write Ports
  input       writeValidIn,
  output      writeReadyOut,
  input [7:0] writeAsciiDataIn,
  input [8:0] writeBaseAddrIn,

  // Update Ports
  input  updateValidIn,
  output updateReadyOut,
  input  updateClearIn,

  // Display Control
  input  displayOnValidIn,
  output displayOnReadyOut,
  input  displayOffValidIn,
  output displayOffReadyOut,
  input  displayToggleValidIn,
  output displayToggleReadyOut,

  // OLED SPI
  output SCLK,
  output SS,
  output MOSI,

  // OLED Discrete Control
  output logic DC,   // Active Low
  output logic RES,  // Active Low
  output logic VBAT, // Active Low
  output logic VDD   // Active Low
);

// Init State Machine
typedef enum {VDD_ON, DISP_OFF, RES_ON, RES_OFF, CHG_PM1, CHG_PM2,
              PRE_CHG1, PRE_CHG2, VBAT_ON, DISP_CON1, DISP_CON2, SET_SEG_REMAP,
              SET_SCAN_DIR, SET_LOW_COL, LOW_COL_ADDR, DISP_ON, FINISH} OLED_INIT_ENUM;

(* MARK_DEBUG = "TRUE" *) OLED_INIT_ENUM initState = VDD_ON;

// millisecond delay
(* MARK_DEBUG = "TRUE" *) integer msDelayCnt   = 0;
(* MARK_DEBUG = "TRUE" *) logic msDelayStart = 0;
(* MARK_DEBUG = "TRUE" *) logic msDelayDone  = 0;

// Delay Count
(* MARK_DEBUG = "TRUE" *) integer delayCnt = 0;

// SPI
(* MARK_DEBUG = "TRUE" *) logic initSpiValid;
(* MARK_DEBUG = "TRUE" *) logic [7:0] initSpiData;
(* MARK_DEBUG = "TRUE" *) logic useSpiValid;
(* MARK_DEBUG = "TRUE" *) logic [7:0] useSpiData;
(* MARK_DEBUG = "TRUE" *) logic spiValid;
(* MARK_DEBUG = "TRUE" *) logic spiReady;
(* MARK_DEBUG = "TRUE" *) logic [7:0] spiData;

// OLED CTRL
(* MARK_DEBUG = "TRUE" *) logic initDC = 'b1;
(* MARK_DEBUG = "TRUE" *) logic initRES = 'b1;
(* MARK_DEBUG = "TRUE" *) logic initVBAT = 'b1;
(* MARK_DEBUG = "TRUE" *) logic initVDD = 'b1;

// Using State Machine
typedef enum {INIT, IDLE, TOGGLE, UPDATE_PAGE, UPDATE_SCREEN, SEND_BYTE} OLED_SM_ENUM;

(* MARK_DEBUG = "TRUE" *) OLED_SM_ENUM state;

// Page
(* MARK_DEBUG = "TRUE" *) integer updatePageCnt = 0;

// Screen
(* MARK_DEBUG = "TRUE" *) integer index = 0;
(* MARK_DEBUG = "TRUE" *) integer page = 0;
(* MARK_DEBUG = "TRUE" *) logic [7:0] data = 0;
logic toggle = 0;

assign displayOnReadyOut = (state == IDLE && displayOnValidIn == 'b0) ? 'b1 : 'b0;

spi_controller spi (
  .sysClkIn(sysClkIn),
  .sysRstIn(sysRstIn),
  .tValidIn(spiValid),
  .tReadyOut(spiReady),
  .tDataIn(spiData),
  .SCLK(SCLK),
  .SS(SS),
  .MOSI(MOSI),
  .MISO()
);

always@(posedge sysClkIn)
begin
  if (msDelayStart == 'b1)
  begin
    if (msDelayCnt == 100000)
    begin
      msDelayDone <= 'b1;
      msDelayCnt  <= 0;
    end else begin
      msDelayDone <= 'b0;
      msDelayCnt  <= msDelayCnt + 1;
    end
   end else begin
    msDelayDone <= 'b0;
    msDelayCnt  <= 0;
  end
end

assign spiValid = (state == INIT) ? initSpiValid : useSpiValid;
assign spiData = (state == INIT) ? initSpiData : useSpiData;

always@(posedge sysClkIn or posedge sysRstIn)
begin
  if (sysRstIn == 'b1)
  begin
    updatePageCnt <= 0;
    index <= 0;
    page <= 0;
    data <= 'h00;
    useSpiValid <= 'b0;
    useSpiData  <= 'b0;
    state <= INIT;
  end else begin
    case (state)
      INIT: begin
        if (initState == FINISH)
        begin
            data  <= 'h00;
            
            if (spiReady == 'b1)
              state <= UPDATE_PAGE;
            else
              state <= INIT;
        end else begin
            // Init OLED Control
            DC    <= initDC;
            RES   <= initRES;
            VBAT  <= initVBAT;
            VDD   <= initVDD;
            state <= INIT;
        end
      end
  
      IDLE: begin
        useSpiValid <= 'b0;
        index <= 0;
        page  <= 0;
        updatePageCnt <= 0;
        
        if (displayOffValidIn == 'b1)
          state <= TOGGLE;
        else if (displayToggleValidIn == 'b1)
        begin
          data <= 'h55;
          state <= UPDATE_PAGE;
        end else
          state <= IDLE;
      end
  
      TOGGLE: begin
        DC <= 'b0;
        useSpiValid <= 'b0;
  
        if (spiReady == 'b1)
        begin
          toggle <= ~toggle;
          useSpiData  <= 8'hA4 | {7'b0, ~toggle};
          useSpiValid <= 'b1;
          state    <= IDLE;
        end
      end
  
      UPDATE_PAGE: begin
        case (updatePageCnt)
          0: useSpiData <= 8'h22;
          1: useSpiData <= {6'b0, page};
          2: useSpiData <= 8'h00;
          3: useSpiData <= 8'h10;
        endcase
  
        if (page == 'd4)
          state <= IDLE;
        else if (updatePageCnt < 4)
        begin
          DC <= 'b0;
          
          useSpiValid <= 'b0;
          if (spiReady == 'b1)
          begin
            updatePageCnt <= updatePageCnt + 1;
            useSpiValid   <= 'b1;
          end
  
          state <= UPDATE_PAGE;
  
        end else begin
          useSpiValid <= 'b0;
          
          if (spiReady == 'b1)
            state <= UPDATE_SCREEN;
          else
            state <= UPDATE_PAGE;
        end
      end
  
      UPDATE_SCREEN: begin
        useSpiValid <= 'b0;
        if (index == 8'd128)
        begin
          if (spiReady == 'b1)
          begin
            index <= 'b0;
            page  <= page + 1;
            updatePageCnt <= 0;
            state <= UPDATE_PAGE;
          end else
            state <= UPDATE_SCREEN;
        end else begin
          useSpiData <= data;
          index <= index + 1;
          state <= SEND_BYTE;
        end  
      end
  
      SEND_BYTE: begin
        DC <= 'b1;
  
        useSpiValid <= 'b0;
        if (spiReady == 'b1)
        begin
          // Default to clear the screen
          useSpiData  <= data;
          useSpiValid <= 'b1;
          state <= UPDATE_SCREEN;
        end
      end

    endcase
  end
end

always@(posedge sysClkIn or posedge sysRstIn)
begin

  if (sysRstIn == 'b1)
  begin
    initDC    <= 'b1;
    initRES   <= 'b1;
    initVDD   <= 'b1;
    initVBAT  <= 'b1;
    initState <= VDD_ON;
  end else begin

      case (initState)
          VDD_ON: begin
              initSpiValid <= 'b0;
              initDC  <= 'b0;
              initVDD <= 'b0;

              msDelayStart <= 'b1;

              if (msDelayDone == 'b1)
              begin
                  msDelayStart <= 'b0;
                  initState    <= DISP_OFF;
              end
          end

          DISP_OFF: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hAE;
                  initSpiValid <= 'b1;
                  initState    <= RES_ON;
              end
          end

          RES_ON: begin
              initSpiValid <= 'b0;
              initRES <= 'b0;

              msDelayStart <= 'b1;
              if (msDelayDone == 'b1)
              begin
                  msDelayStart <= 'b0;
                  initState    <= RES_OFF;
              end
          end

          RES_OFF: begin
              initSpiValid <= 'b0;
              initRES <= 'b1;

              msDelayStart <= 'b1;
              if (msDelayDone == 'b1)
              begin
                  msDelayStart <= 'b0;
                  initState    <= CHG_PM1;
              end
          end

          CHG_PM1: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'h8d;
                  initSpiValid <= 'b1;
                  initState    <= CHG_PM2;
              end
          end

          CHG_PM2: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'h14;
                  initSpiValid <= 'b1;
                  initState    <= PRE_CHG1;
              end
          end

          PRE_CHG1: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hD9;
                  initSpiValid <= 'b1;
                  initState    <= PRE_CHG2;
              end
          end

          PRE_CHG2: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hF1;
                  initSpiValid <= 'b1;
                  initState    <= VBAT_ON;
              end
          end

          VBAT_ON: begin
              initSpiValid <= 'b0;
              initVBAT <= 'b0;

              msDelayStart <= 'b1;
              if (msDelayDone == 'b1)
                  delayCnt <= delayCnt + 1;

              if (delayCnt == 64)
              begin
                  msDelayStart <= 'b0;
                  delayCnt     <= 0;
                  initState    <= DISP_CON1;
              end
          end

          DISP_CON1: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'h81;
                  initSpiValid <= 'b1;
                  initState    <= DISP_CON2;
              end
          end

          DISP_CON2: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'h0F;
                  initSpiValid <= 'b1;
                  initState    <= SET_SEG_REMAP;
              end
          end

          SET_SEG_REMAP: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hA0;
                  initSpiValid <= 'b1;
                  initState    <= SET_SCAN_DIR;
              end
          end

          SET_SCAN_DIR: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hC0;
                  initSpiValid <= 'b1;
                  initState    <= SET_LOW_COL;
              end
          end

          SET_LOW_COL: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hDA;
                  initSpiValid <= 'b1;
                  initState    <= LOW_COL_ADDR;
              end
          end

          LOW_COL_ADDR: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'h00;
                  initSpiValid <= 'b1;
                  initState    <= DISP_ON;
              end
          end

          DISP_ON: begin
              initSpiValid <= 'b0;
              if (spiReady == 'b1)
              begin
                  initSpiData  <= 8'hAF;
                  initSpiValid <= 'b1;
                  initState    <= FINISH;
              end
          end

          FINISH: begin
            initSpiValid <= 'b0;
            initState    <= FINISH;
          end
     endcase
  end
end

endmodule

