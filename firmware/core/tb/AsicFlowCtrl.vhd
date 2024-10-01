-- only for simulation

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity AsicFlowCtrl is
    generic (
        RST_POLARITY_G      : sl      := '1';    -- '1' for active HIGH reset, '0' for active LOW reset
        TIMEOUT_CNT_WIDTH   : integer := 4;  -- in bit-size
        TIMEOUT_CNT_LIMIT   : integer := 15; -- in decimal counts
        USE_PIX2PGP_BUSY    : boolean := true; -- use pix2pgp state in FSM
        USE_SPARSE_ITF_BUSY : boolean := true  -- use sparse_itf state in FSM
    );
    port (
        clk                : in std_logic;       -- global clk of the whole digital (including balcony)
        df_reset_n        : in  std_logic := not RST_POLARITY_G;     -- separate reset signal for adc_sampl dff (x4): active LOW
        sro                : in std_logic;       -- start of frame signal (SRO_sync)
        tok_fb             : in std_logic;       -- end of frame signal   (tok_fb_sync)
        sparse_itf_busy    : in std_logic;       -- sparse interface block busy
        pix2pgp_busy       : in std_logic;       -- columnManager 'busy' signal; for handshaking
        sof                : out std_logic;      -- start-of-frame
        eof                : out std_logic;      -- end-of-frame
        over_occ           : out std_logic       -- overOccupancy
    );
end entity;

architecture rtl of AsicFlowCtrl is
    type state_type is (IDLE, WAIT_TOKFB_HIGH, IN_FRAME);
    signal state       : state_type := IDLE;
    signal tok_fb_dly  : std_logic := '0';
    signal sro_dly     : std_logic := '0';
    signal tok_fb_negedge : std_logic := '0';
    signal tok_fb_posedge : std_logic := '0';
    signal sro_posedge : std_logic := '0';
    signal arm_cnt     : std_logic := '0';
    signal tok_fb_settled : std_logic := '0';
    signal over_occ_flag : std_logic := '0';

    -- Watchdog signals
    signal done        : std_logic;

begin
    -- Edge detection for tok_fb
    process(clk)
    begin
        if rising_edge(clk) then
            tok_fb_dly <= tok_fb;
            tok_fb_negedge <= tok_fb_dly and not tok_fb;
            tok_fb_posedge <= tok_fb and not tok_fb_dly;
        end if;
    end process;

    -- Edge detection for sro
    process(clk)
    begin
        if rising_edge(clk) then
            sro_dly <= sro;
            sro_posedge <= sro and not sro_dly;
        end if;
    end process;

    -- FSM process
    process(clk, df_reset_n)
    begin
        if df_reset_n = RST_POLARITY_G then
            state <= IDLE;
            sof <= '0';
            eof <= '0';
            arm_cnt <= '0';
            over_occ <= '0';
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    -- missed handshaking between columnManager and this FSM; safeguard end-of-frame
                    eof <= ite(USE_PIX2PGP_BUSY, pix2pgp_busy, '0');

                    -- make sure token-feedback settling counter (watchdog) is reset
                    arm_cnt <= '0';

                    if tok_fb_negedge = '1' and
                       (USE_PIX2PGP_BUSY = false or (pix2pgp_busy = '0' and USE_PIX2PGP_BUSY = true)) then
                        sof <= '1';
                        state <= WAIT_TOKFB_HIGH;
                    end if;

                when WAIT_TOKFB_HIGH =>
                    -- one-cycle toggle
                    sof <= '0';
                    over_occ <= '0'; -- one-cycle toggle
                    arm_cnt <= '0';

                    if tok_fb_posedge = '1' then
                        state <= IN_FRAME;
                    end if;

                when IN_FRAME =>
                    arm_cnt <= tok_fb_dly;

                    if sro_posedge = '1' then -- over-occ takes precedence
                        eof <= '0'; -- frame not properly closed
                        over_occ <= '1'; -- raise over-occ flag
                        state <= WAIT_TOKFB_HIGH; -- go back to previous state; event botched
                    elsif tok_fb_settled = '1' and
                          (USE_SPARSE_ITF_BUSY = false or (sparse_itf_busy = '0' and USE_SPARSE_ITF_BUSY = true)) then
                        eof <= '1'; -- close the frame properly
                        over_occ <= '0'; -- normal case, not over-occ
                        state <= IDLE; -- done! back to IDLE
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Instantiate the watchdog component
    U_Pix2PgpWatchdog : entity pix2pgp.Pix2PgpWatchdog
        generic map (
            TPD_G          => 1 ns,
            RST_ASYNC_G    => true,
            CNT_WIDTH_G    => TIMEOUT_CNT_WIDTH,
            RST_POLARITY_G => RST_POLARITY_G)
        port map (
            clk => clk,
            rst => df_reset_n,
            set => arm_cnt,
            timeout => tok_fb_settled
        );

end architecture rtl;
