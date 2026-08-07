// First-slice redirect arbiter for resolved scalar control flow.
module edge_pc_redirect_ctrl #(
  parameter PC_WIDTH     = 40,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH  = 4
) (
  input  wire                    forever_cpuclk,
  input  wire                    cpurst_b,

  input  wire                    scalar_control_valid,
  input  wire                    scalar_control_taken,
  input  wire [PC_WIDTH-1:0]     scalar_control_target,
  input  wire [SEQ_ID_WIDTH-1:0] scalar_control_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  scalar_control_epoch,

  input  wire                    retire_redirect_valid,
  input  wire [PC_WIDTH-1:0]     retire_redirect_pc,
  input  wire [SEQ_ID_WIDTH-1:0] retire_redirect_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  retire_redirect_epoch,

  input  wire                    loop_predict_valid,
  input  wire [PC_WIDTH-1:0]     loop_predict_target,
  input  wire [PC_WIDTH-1:0]     loop_predict_fallthrough,
  input  wire [SEQ_ID_WIDTH-1:0] loop_predict_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  loop_predict_epoch,

  output wire                    ifu_redirect_valid,
  output wire [PC_WIDTH-1:0]     ifu_redirect_pc,
  output wire [EPOCH_WIDTH-1:0]  ifu_redirect_epoch,

  output wire                    redirect_flush_valid,
  output wire                    redirect_predict_valid,
  output wire [SEQ_ID_WIDTH-1:0] redirect_kill_seq_id,
  output wire [EPOCH_WIDTH-1:0]  redirect_kill_epoch,
  output wire [EPOCH_WIDTH-1:0]  redirect_new_epoch,
  output wire [EPOCH_WIDTH-1:0]  current_epoch
);

  reg [EPOCH_WIDTH-1:0] current_epoch_r;
  reg                   predicted_valid_r;
  reg [SEQ_ID_WIDTH-1:0] predicted_seq_id_r;
  reg [EPOCH_WIDTH-1:0]  predicted_branch_epoch_r;
  reg [EPOCH_WIDTH-1:0]  predicted_path_epoch_r;
  reg [PC_WIDTH-1:0]     predicted_target_r;
  reg [PC_WIDTH-1:0]     predicted_fallthrough_r;

  wire scalar_redirect_valid;
  wire scalar_matches_new_prediction;
  wire scalar_matches_prediction;
  wire scalar_prediction_miss;
  wire loop_predict_selected;
  wire loop_predict_resolved_same_cycle;
  wire [PC_WIDTH-1:0] scalar_actual_pc;
  wire [PC_WIDTH-1:0] scalar_predicted_target;
  wire [PC_WIDTH-1:0] scalar_predicted_fallthrough;
  wire [EPOCH_WIDTH-1:0] scalar_predicted_path_epoch;
  wire [PC_WIDTH-1:0] selected_redirect_pc;
  wire [SEQ_ID_WIDTH-1:0] selected_kill_seq_id;
  wire [EPOCH_WIDTH-1:0] selected_kill_epoch;
  wire redirect_fire;
  wire [EPOCH_WIDTH-1:0] next_epoch;

  assign scalar_matches_new_prediction =
    loop_predict_valid &&
    scalar_control_valid &&
    (scalar_control_seq_id == loop_predict_seq_id) &&
    (scalar_control_epoch == loop_predict_epoch);
  assign scalar_matches_prediction =
    predicted_valid_r &&
    scalar_control_valid &&
    (scalar_control_seq_id == predicted_seq_id_r) &&
    (scalar_control_epoch == predicted_branch_epoch_r);
  assign scalar_predicted_target = scalar_matches_new_prediction ?
                                   loop_predict_target : predicted_target_r;
  assign scalar_predicted_fallthrough = scalar_matches_new_prediction ?
                                        loop_predict_fallthrough :
                                        predicted_fallthrough_r;
  assign scalar_predicted_path_epoch = scalar_matches_new_prediction ?
                                       next_epoch : predicted_path_epoch_r;
  assign scalar_actual_pc = scalar_control_taken ? scalar_control_target :
                                                   scalar_predicted_fallthrough;
  assign scalar_prediction_miss =
    (scalar_matches_prediction || scalar_matches_new_prediction) &&
    (scalar_actual_pc != scalar_predicted_target);
  assign scalar_redirect_valid =
    scalar_control_valid &&
    ((scalar_matches_prediction && scalar_prediction_miss) ||
     (scalar_matches_new_prediction && scalar_prediction_miss) ||
     (!scalar_matches_prediction && !scalar_matches_new_prediction &&
      scalar_control_taken));
  assign redirect_fire = retire_redirect_valid ||
                         scalar_redirect_valid ||
                         loop_predict_valid;
  assign loop_predict_selected = loop_predict_valid &&
                                 !retire_redirect_valid &&
                                 !scalar_redirect_valid;
  assign loop_predict_resolved_same_cycle =
    scalar_control_valid &&
    (scalar_control_seq_id == loop_predict_seq_id) &&
    (scalar_control_epoch == loop_predict_epoch);
  assign next_epoch = current_epoch_r + {{(EPOCH_WIDTH-1){1'b0}}, 1'b1};
  assign selected_redirect_pc =
    retire_redirect_valid ? retire_redirect_pc :
    (scalar_redirect_valid ? scalar_actual_pc : loop_predict_target);
  assign selected_kill_seq_id =
    retire_redirect_valid ? retire_redirect_seq_id :
    (scalar_prediction_miss ? {SEQ_ID_WIDTH{1'b0}} :
     (scalar_redirect_valid ? scalar_control_seq_id : loop_predict_seq_id));
  assign selected_kill_epoch =
    retire_redirect_valid ? retire_redirect_epoch :
    (scalar_prediction_miss ? scalar_predicted_path_epoch :
     (scalar_redirect_valid ? scalar_control_epoch : loop_predict_epoch));

  assign ifu_redirect_valid = redirect_fire;
  assign ifu_redirect_pc = selected_redirect_pc;
  assign ifu_redirect_epoch = next_epoch;

  assign redirect_flush_valid = redirect_fire;
  assign redirect_predict_valid = loop_predict_valid && !retire_redirect_valid;
  assign redirect_kill_seq_id = selected_kill_seq_id;
  assign redirect_kill_epoch = selected_kill_epoch;
  assign redirect_new_epoch = next_epoch;
  assign current_epoch = current_epoch_r;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      current_epoch_r <= {EPOCH_WIDTH{1'b0}};
      predicted_valid_r <= 1'b0;
      predicted_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      predicted_branch_epoch_r <= {EPOCH_WIDTH{1'b0}};
      predicted_path_epoch_r <= {EPOCH_WIDTH{1'b0}};
      predicted_target_r <= {PC_WIDTH{1'b0}};
      predicted_fallthrough_r <= {PC_WIDTH{1'b0}};
    end else if (redirect_fire) begin
      current_epoch_r <= next_epoch;
      if (loop_predict_selected && !loop_predict_resolved_same_cycle) begin
        predicted_valid_r <= 1'b1;
        predicted_seq_id_r <= loop_predict_seq_id;
        predicted_branch_epoch_r <= loop_predict_epoch;
        predicted_path_epoch_r <= next_epoch;
        predicted_target_r <= loop_predict_target;
        predicted_fallthrough_r <= loop_predict_fallthrough;
      end else if (retire_redirect_valid || scalar_matches_prediction ||
                   scalar_matches_new_prediction) begin
        predicted_valid_r <= 1'b0;
      end
    end else if (scalar_matches_prediction || scalar_matches_new_prediction) begin
      predicted_valid_r <= 1'b0;
    end
  end

endmodule
