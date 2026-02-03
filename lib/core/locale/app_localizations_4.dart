const Map<String, Map<String, String>> appLocalizationsPart4 = {
  'en': {
    'common_add': 'Add',
    'common_you': 'You',
    'common_yes': 'Yes',
    'common_no': 'No',
    'common_none': '(none)',
    'common_cancel': 'Cancel',
    'common_later': 'Later',
    'common_pay_now': 'Pay now',
    'common_paste': 'Paste',
    'common_continue': 'Continue',
    'common_done': 'Done',
    'common_open': 'Open',
    'common_retry': 'Retry',
    'common_copy': 'Copy',

    'add_teams_appbar_title_prefix': 'Add Teams',
    'add_teams_header_title': 'Add players (by UserId)',

    'add_teams_format_classic': 'Classic',
    'add_teams_format_ucl_group': 'UCL Group',
    'add_teams_format_ucl_swiss': 'UCL Swiss',

    'add_teams_unlock_group': 'Save anytime. Fixtures unlock at exactly 16 or 32 teams.',
    'add_teams_unlock_swiss': 'Save anytime. Fixtures unlock at exactly 18 or 36 teams.',
    'add_teams_unlock_classic': 'Save anytime. Fixtures unlock at 2+ teams.',

    'add_teams_league_pool': 'League Pool',
    'add_teams_unassigned': 'Unassigned',

    'add_teams_group_a': 'Group A',
    'add_teams_group_b': 'Group B',
    'add_teams_group_c': 'Group C',
    'add_teams_group_d': 'Group D',
    'add_teams_group_e': 'Group E',
    'add_teams_group_f': 'Group F',
    'add_teams_group_g': 'Group G',
    'add_teams_group_h': 'Group H',

    'add_teams_max_teams_error_prefix': 'Maximum',
    'add_teams_max_teams_error_suffix': 'teams allowed for this format.',
    'add_teams_user_already_added': 'This user is already added to this league.',

    'add_teams_add_players_title': 'Add players',
    'add_teams_saved_prefix': 'Saved: ',
    'add_teams_new_prefix': 'New: ',

    'add_teams_add_one_player': 'Add one player',
    'add_teams_paste_list': 'Paste a list',
    'add_teams_import_csv': 'Import CSV roster',

    'add_teams_add_player_by_userid_title': 'Add player by UserId',
    'add_teams_userid_hint': 'eS44e35f  (or Firebase uid)',
    'add_teams_lookup_tooltip': 'Lookup',
    'add_teams_resolved_profile_title': 'Resolved profile',
    'add_teams_uid_prefix': 'uid: ',
    'add_teams_will_be_placed_in_prefix': 'Will be placed in: ',
    'add_teams_no_profile_found_help':
        'No profile found for this UserId. Ask the player to login once and share their UserId (eSxxxxxx).',
    'add_teams_lookup_failed_prefix': 'Lookup failed:',

    'add_teams_paste_userids_title': 'Paste UserIds',
    'add_teams_paste_userids_subtitle':
        'Paste one per line (or comma-separated). Use short UserId (eSxxxxxx) or Firebase uid.',
    'add_teams_paste_hint': 'eS44e35f\neS91a2b3\nuid_3',
    'add_teams_paste_at_least_one_userid': 'Paste at least one UserId.',
    'add_teams_validation_failed_prefix': 'Validation failed:',

    'add_teams_clear': 'Clear',
    'add_teams_validate': 'Validate',
    'add_teams_bulk_ok_prefix': 'OK: ',
    'add_teams_bulk_not_found_prefix': 'Not found: ',
    'add_teams_no_profile_found_short': 'No profile found',
    'add_teams_add_valid': 'Add valid',

    'add_teams_saved_toast': 'Teams saved.',

    'add_teams_cannot_generate_group_prefix':
        'Cannot generate fixtures: UCL Group requires exactly 16 or 32 teams. Current: ',
    'add_teams_cannot_generate_swiss_prefix':
        'Cannot generate fixtures: Swiss requires exactly 18 or 36 teams. Current: ',
    'add_teams_cannot_generate_classic_prefix':
        'Cannot generate fixtures: Classic requires at least 2 teams. Current: ',

    'add_teams_swiss_fixtures_already_exist':
        'Swiss fixtures already exist. Generate later rounds from the Swiss round generator.',

    'add_teams_regenerate_fixtures_title': 'Regenerate fixtures?',
    'add_teams_regenerate_fixtures_message':
        'Fixtures already exist. Regenerating will reset all match results.\n\nContinue?',
    'add_teams_regenerate': 'Regenerate',

    'add_teams_invalid_group_structure_prefix': 'Invalid group structure. For',
    'add_teams_invalid_group_structure_suffix': 'teams you must have groups of 4 with correct group names.',

    'add_teams_failed_generate_fixtures': 'Failed to generate fixtures.',
    'add_teams_fixtures_generated_prefix': 'Fixtures generated (',
    'add_teams_fixtures_generated_suffix': ' matches).',

    'add_teams_current_group': 'Current group',
    'add_teams_review_teams': 'Review teams',
    'add_teams_empty_state':
        'No teams yet.\nTap "Add one player", "Paste a list", or "Import CSV roster".',

    'add_teams_label_saved': 'Saved',
    'add_teams_label_new': 'New',

    'add_teams_save_teams': 'Save teams',
    'add_teams_generate_fixtures': 'Generate fixtures',

    'add_teams_team_details_title': 'Team details',
    'add_teams_team_name_label': 'Team name',
    'add_teams_uid_internal_label': 'uid (internal)',
    'add_teams_group_label': 'Group',
    'add_teams_save_changes': 'Save changes',
    'add_teams_remove_team': 'Remove team',

    'league_space_appbar_title': 'League Space',
    'league_space_default_title': 'League Space',
    'league_space_live_badge': 'LIVE',
    'league_space_ended_badge': 'ENDED',
    'league_space_host_prefix': 'Host: ',

    'league_space_failed_to_parse_space_prefix': 'Failed to parse space:',
    'league_space_stream_error_prefix': 'Space stream error:',
    'league_space_audio_connect_failed_prefix': 'Audio connect failed:',

    'league_space_no_active_space': 'No active space right now.\nAsk the organizer to start one.',

    'league_space_join_audio': 'Join Audio',
    'league_space_leave_audio': 'Leave Audio',

    'league_space_mic_on': 'Mic ON',
    'league_space_mic_off': 'Mic OFF',

    'league_space_connected_as_host': 'Connected as host',
    'league_space_connected_as_speaker': 'Connected as speaker',
    'league_space_connected_as_speaker_muted_by_host': 'Connected as speaker (muted by host)',
    'league_space_connected_as_listener': 'Connected as listener (mic muted)',
    'league_space_not_connected': 'Not connected to audio',

    'league_space_space_not_live': 'Space is not live.',
    'league_space_request_sent': 'Request sent.',
    'league_space_request_failed_prefix': 'Request failed:',
    'league_space_request_removed': 'Request removed.',
    'league_space_failed_prefix': 'Failed:',

    'league_space_mic_not_primed_toast':
        'Mic not primed (permission denied). Leave/rejoin after granting mic permission.',
    'league_space_mic_unavailable_permission_denied':
        'Mic unavailable (permission denied on join). Leave/rejoin after granting mic permission.',
    'league_space_mic_unavailable': 'Mic unavailable.',
    'league_space_you_are_muted_by_host': 'You are muted by the host.',
    'league_space_request_to_speak_to_enable_mic': 'Request to speak to enable your mic.',

    'league_space_you_are_speaker': 'You are a speaker',
    'league_space_request_pending': 'Request Pending',
    'league_space_request_to_speak': 'Request to Speak',
    'league_space_request_denied': 'Request denied.',

    'league_space_toast_now_speaker': 'You are now a speaker.',
    'league_space_toast_now_listener': 'You are now a listener.',
    'league_space_toast_host_muted_you': 'Host muted you.',
    'league_space_toast_host_unmuted_you': 'Host unmuted you.',

    'league_space_host_panel_title': 'Host Panel',

    'league_space_requests_title': 'Requests',
    'league_space_requests_error_prefix': 'Requests error:',
    'league_space_no_pending_requests': 'No pending requests.',

    'league_space_uid_prefix': 'uid: ',
    'league_space_wants_to_speak_suffix': '• wants to speak',

    'league_space_deny': 'Deny',
    'league_space_approve': 'Approve',
    'league_space_deny_failed_prefix': 'Deny failed:',
    'league_space_approve_failed_prefix': 'Approve failed:',

    'league_space_approved_prefix': 'Approved ',
    'league_space_denied_prefix': 'Denied ',
    'league_space_removed_speaker_prefix': 'Removed speaker ',
    'league_space_muted_prefix': 'Muted ',
    'league_space_unmuted_prefix': 'Unmuted ',

    'league_space_speakers_title': 'Speakers',
    'league_space_speakers_error_prefix': 'Speakers error:',
    'league_space_no_speakers_yet': 'No speakers yet.',

    'league_space_muted': 'Muted',
    'league_space_unmuted': 'Unmuted',

    'league_space_mute': 'Mute',
    'league_space_unmute': 'Unmute',
    'league_space_remove': 'Remove',

    'league_space_mute_failed_prefix': 'Mute failed:',
    'league_space_remove_failed_prefix': 'Remove failed:',

    'league_create_wizard_step_basics': 'Basics',
    'league_create_wizard_step_rules': 'Rules',
    'league_create_wizard_step_review': 'Review',
    'league_create_wizard_tournament_format_label': 'Tournament format',
    'league_create_wizard_double_rr_label': 'Double RR',
    'league_create_wizard_double_round_robin_title': 'Double Round Robin',
    'league_create_wizard_double_round_robin_subtitle': 'Home & Away legs (if applicable)',
    'league_create_wizard_description_label': 'Description',

    'league_access_charges_required_title': 'App Charges Required',
    'league_access_amount_prefix': 'Amount:',
    'league_access_charges_explanation':
        'To view Fixtures and Standings for Series/Group leagues, participants must pay app charges.',
    'league_access_league_prefix': 'League:',
    'league_access_receipt_prefix': 'Receipt:',
    'league_access_pay_charges': 'Pay Charges',
    'league_access_note_classic_free': 'Classic leagues are free. League creators always have full access.',
    'league_access_charges_paid_success': 'Charges paid successfully',
    'league_access_payment_failed_prefix': 'Payment failed:',

    'league_creation_payment_appbar_title': 'League Creation Charges',
    'league_creation_payment_required_title': 'Payment Required',
    'league_creation_payment_amount_prefix': 'Amount:',
    'league_creation_payment_explanation_prefix':
        'To create this Series/Group league, you must pay app charges.\n\nLeague:',
    'league_creation_payment_provider_prefix': 'Provider:',
    'league_creation_payment_failed_prefix': 'Payment failed:',
    'league_creation_payment_pay_continue': 'Pay & Continue',

    'league_participants_appbar_title': 'Participants',
    'league_participants_empty_title': 'No participants yet',
    'league_participants_empty_subtitle':
        'Participants will appear here after they join via code/QR or are assigned to teams.',
    'league_participants_organizers_title': 'Organizers',
    'league_participants_participants_title': 'Participants',
    'league_participants_no_team': 'No team',
    'league_participants_team_prefix': 'Team ',
    'league_participants_role_organizer': 'Organizer',
    'league_participants_userid_prefix': 'userId: ',

    'admin_knockout_appbar_title': 'Knockout Score Management',
    'admin_knockout_reload_tooltip': 'Reload',
    'admin_knockout_section_title': 'Update Knockout Results',
    'admin_knockout_section_description':
        'Update scores for Play-off, Round of 16, and beyond.\n'
            'Winners automatically advance to the next round.\n'
            'Rules enforced:\n'
            '• Single-match knockouts cannot end in a draw (penalties winner required)\n'
            '• 2-legged Play-offs advance only after Leg 2; aggregate ties require penalties winner',
    'admin_knockout_empty_state':
        'No knockout matches found.\nGenerate the bracket from the league details screen first.',

    'admin_knockout_round_playoff': 'Play-off',
    'admin_knockout_round_r16': 'Round of 16',
    'admin_knockout_round_quarter_finals': 'Quarter Finals',
    'admin_knockout_round_semi_finals': 'Semi Finals',
    'admin_knockout_round_final': 'Final',
    'admin_knockout_round_third_place': '3rd Place',

    'admin_knockout_penalties_title': 'Penalties / Tiebreak Required',
    'admin_knockout_select_winner_to_advance': 'Select the winner to advance.',

    'admin_knockout_cannot_save_draw_tbd': 'Cannot save a draw for a TBD match. Set teams first.',
    'admin_knockout_draw_requires_winner': 'This knockout match ended in a draw.',
    'admin_knockout_winner_required': 'Winner required to advance.',
    'admin_knockout_aggregate_tied_after_leg2': 'Aggregate is tied after Leg 2.',
    'admin_knockout_aggregate_winner_required': 'Winner required to advance from an aggregate tie.',

    'admin_knockout_score_updated_toast': 'Knockout score updated',

    'admin_knockout_leg1': 'Leg 1',
    'admin_knockout_leg2': 'Leg 2',

    'admin_knockout_status_completed': 'Completed',
    'admin_knockout_status_pending': 'Pending',

    'knockout_bracket_appbar_title': 'Knockout Bracket',
    'knockout_bracket_reload_tooltip': 'Reload',
    'knockout_bracket_empty_state':
        'No knockout matches found.\nGenerate the bracket from the league details screen first.',
    'knockout_bracket_header_title': 'Knockout Bracket',
    'knockout_bracket_matches_scheduled_suffix': 'matches scheduled',
    'knockout_bracket_aggregate_prefix': 'Aggregate: ',
    'knockout_bracket_penalties_prefix': 'Penalties: ',
    'knockout_bracket_aggregate_tied_penalties_required': 'Aggregate tied — penalties winner required.',
    'knockout_bracket_draw_winner_required': 'Draw — winner required.',

    'admin_score_appbar_title': 'Score Management',
    'admin_score_section_title': 'Update Match Results',

    'admin_score_generate_classic': 'GENERATE CLASSIC FIXTURES',
    'admin_score_generate_group': 'GENERATE GROUP FIXTURES',
    'admin_score_generate_next_swiss_round': 'GENERATE NEXT SWISS ROUND',

    'admin_score_help_text':
        'Tap + / - to adjust each team\'s score.\n'
            'Use group and round filters to quickly find matches.\n'
            'Pending matches are listed first; completed go to the bottom.',

    'admin_score_toast_score_updated': 'Score Updated Successfully',

    'admin_score_not_enough_teams': 'Not enough teams to generate fixtures.',
    'admin_score_fixtures_already_exist': 'Fixtures already exist.',
    'admin_score_failed_generate_fixtures': 'Failed to generate fixtures.',
    'admin_score_fixtures_generated_prefix': 'Fixtures generated (',
    'admin_score_fixtures_generated_suffix': ' matches).',

    'admin_score_group_team_count_error_prefix': 'UCL Group supports only 16 or 32 teams. Current: ',
    'admin_score_complete_group_draw_first': 'Complete group draw first (all groups must have exactly 4 teams).',
    'admin_score_group_fixtures_already_exist': 'Group fixtures already exist.',
    'admin_score_failed_generate_group_fixtures': 'Failed to generate group fixtures.',
    'admin_score_group_fixtures_generated_prefix': 'Group fixtures generated (',

    'admin_score_swiss_team_count_error_prefix': 'Swiss format supports only 18 or 36 teams. Current: ',
    'admin_score_swiss_even_team_count_required': 'Swiss league phase requires an even number of teams (no byes).',

    'admin_score_complete_round_prefix': 'Complete all matches in Round ',
    'admin_score_complete_round_suffix': ' before generating the next round.',
    'admin_score_all_swiss_rounds_generated_prefix': 'All ',
    'admin_score_all_swiss_rounds_generated_suffix': ' Swiss rounds have already been generated.',
    'admin_score_round_already_exists_prefix': 'Round ',
    'admin_score_round_already_exists_suffix': ' already exists.',
    'admin_score_no_swiss_pairings_generated': 'No Swiss pairings could be generated.',
    'admin_score_swiss_round_generated_prefix': 'Swiss round ',
    'admin_score_swiss_round_generated_mid': ' generated (',

    'admin_score_no_matches_to_manage': 'No matches to manage',
    'admin_score_home_fallback': 'Home',
    'admin_score_away_fallback': 'Away',

    'admin_score_all_groups': 'All',
    'admin_score_round_prefix': 'RD ',

    'fixtures_appbar_title': 'Fixtures & Results',
    'fixtures_generate_next_swiss_round_tooltip': 'Generate next Swiss round',
    'fixtures_section_title': 'Matchday Schedule',

    'fixtures_only_organiser_can_generate_swiss_rounds': 'Only the organiser can generate Swiss rounds.',
    'fixtures_league_not_found': 'League not found',
    'fixtures_swiss_team_count_error_prefix': 'Swiss league phase supports only 18 or 36 teams. Current: ',
    'fixtures_no_valid_swiss_pairings':
        'No valid Swiss pairings could be generated (check for existing rematches or constraints).',
    'fixtures_swiss_round_generated_prefix': 'Swiss round ',
    'fixtures_swiss_round_generated_suffix': ' generated',
    'fixtures_failed_generate_swiss_round_prefix': 'Failed to generate Swiss round:',

    'fixtures_no_matches_generated_yet': 'No matches generated yet',
    'fixtures_tbd': 'TBD',

    'group_draw_appbar_title': 'UCL Group Draw',
    'group_draw_only_ucl_group': 'This screen is only for UCL Group leagues.',
    'group_draw_team_count_help_prefix': 'UCL Group Draw supports only 16 or 32 teams.\nCurrent teams: ',
    'group_draw_locked_toast': 'Group draw locked: fixtures already generated.',
    'group_draw_locked_banner': 'Group draw is locked because fixtures already exist.',
    'group_draw_cannot_change_after_fixtures': 'Cannot change groups after fixtures are generated.',
    'group_draw_drawing_teams': 'Drawing teams...',
    'group_draw_resume_draw': 'Resume draw',
    'group_draw_draw_complete': 'Draw complete',
    'group_draw_generate_fixtures': 'Generate fixtures',
    'group_draw_groups_saved_toast': 'Groups saved',
    'group_draw_failed_save_groups_prefix': 'Failed to save groups: ',
    'group_draw_failed_generate_group_fixtures_check_groups':
        'Failed to generate group fixtures. Check group assignments.',

    'standings_appbar_title': 'Standings',
    'standings_section_title': 'League Standings',
    'standings_failed_load_league_prefix': 'Failed to load league.',
    'standings_failed_load_group_standings_prefix': 'Failed to load group standings.',
    'standings_failed_load_standings_prefix': 'Failed to load standings.',
    'standings_no_group_results_yet': 'No group results yet.\nStandings will appear after group matches are played.',
    'standings_ucl_group_structure_warning_prefix':
        'Expected UCL Group to be either 16 teams (4 groups of 4) or 32 teams (8 groups of 4).\nCurrent: ',
    'standings_ucl_group_structure_warning_suffix': ' groups.',
    'standings_no_results_yet': 'No results yet.\nStandings will appear here after matches are played.',
    'standings_swiss_team_count_warning_prefix':
        'This Swiss format supports only 18 or 36 teams.\nCurrent teams: ',
    'standings_swiss_phase_no_rounds_yet_prefix': 'Swiss phase: no rounds yet (max ',
    'standings_swiss_phase_no_rounds_yet_suffix': ' rounds)',
    'standings_swiss_phase_round_prefix': 'Swiss phase: Round ',
    'standings_swiss_phase_round_mid': ' of ',
    'standings_swiss_legend_top8_r16': 'Top 8: Round of 16',
    'standings_swiss_legend_9_24_playoff': '9–24: Play-off',
    'standings_swiss_legend_25_36_eliminated': '25–36: Eliminated',
    'standings_swiss_legend_top4_quarter_finals': 'Top 4: Quarter Finals',
    'standings_swiss_legend_5_12_playoff': '5–12: Play-off',
    'standings_swiss_legend_13_18_eliminated': '13–18: Eliminated',

    'match_detail_appbar_title': 'Match Details',
    'match_detail_vs': 'vs',
    'match_detail_live_section_title': 'Live Match (Gamers Mode)',
    'match_detail_live_section_description':
        'Stream your screen + front camera. Viewers will see both players cams (top-left/top-right) and one player\'s screen (main).',
    'match_detail_copy_live_match_id_tooltip': 'Copy Live Match ID',
    'match_detail_live_id_copied_prefix': 'Live Match ID copied: ',
    'match_detail_open_host_live': 'Open host live',
    'match_detail_opening': 'Opening...',
    'match_detail_tip_text':
        'Tip: Both players can host using the same Match ID.\nViewers on the same Wi-Fi/hotspot can join via Auto-Discovery.',
    'match_detail_streaming_as_title': 'You are streaming as:',
    'match_detail_not_sure_spectator': 'Not sure / Spectator',

    'qr_scanner_permission_error_prefix': 'Permission error: ',
    'qr_scanner_failed_start_camera_prefix': 'Failed to start camera: ',
    'qr_scanner_invalid_qr_join_code': 'Invalid QR / Join code.',
    'qr_scanner_join_failed_prefix': 'Join failed: ',
    'qr_scanner_payment_failed': 'Payment failed',

    'qr_scanner_join_mode_title': 'Join league as...',
    'qr_scanner_join_code_prefix': 'Join code: ',
    'qr_scanner_join_mode_participant_title': 'Participant',
    'qr_scanner_join_mode_participant_subtitle': 'You will be counted as a participant in this league.',
    'qr_scanner_join_mode_viewer_title': 'Viewer only',
    'qr_scanner_join_mode_viewer_subtitle': 'You can browse the league, but you won\'t be counted as a participant.',

    'qr_scanner_joined_league_placeholder_name': 'Joined League',

    'qr_scanner_notice_viewer_but_already_added_team_assigned':
        'You chose Viewer, but you were already added by the organizer as a participant (team assigned).',
    'qr_scanner_notice_already_added_team_assigned': 'You were already added by the organizer (team assigned).',
    'qr_scanner_notice_viewer_but_already_registered_participant':
        'You chose Viewer, but you are already registered as a participant in this league.',
    'qr_scanner_notice_already_registered': 'You are already registered in this league.',
    'qr_scanner_notice_league_full_joined_viewer_only':
        'League is full. You joined as Viewer only (not counted as a participant).',
    'qr_scanner_notice_joined_viewer_only': 'You joined as Viewer only (not counted as a participant).',

    'qr_scanner_unlock_dialog_title': 'Unlock Fixtures & Standings',
    'qr_scanner_unlock_dialog_content_prefix':
        'This league requires charges to view Fixtures and Standings.\n\nLeague: ',
    'qr_scanner_unlock_dialog_content_suffix':
        '\n\nPay now to unlock, or choose Later and pay when you open Fixtures/Standings.',

    'qr_scanner_manual_entry_title': 'Enter Join Code',
    'qr_scanner_manual_entry_subtitle': 'Paste the Join ID (letters/numbers) from the organizer.',
    'qr_scanner_join_code_hint': 'e.g. ABC123',
    'qr_scanner_enter_code_instead': 'Enter code instead',
    'qr_scanner_enter_code': 'Enter code',

    'qr_scanner_joined_appbar_title': 'League Joined',
    'qr_scanner_joined_line_viewer': 'You joined as Viewer (not counted as a participant).',
    'qr_scanner_joined_line_participant': 'You joined as Participant.',
    'qr_scanner_requires_charges_message': 'This league requires charges to view fixtures & standings.',
    'qr_scanner_can_open_league_message': 'You can open the league now.',
    'qr_scanner_unlock_now': 'Unlock now',
    'qr_scanner_teams_suffix': 'teams',

    'qr_scanner_camera_not_available': 'Camera not available',

    'qr_scanner_torch_on_tooltip': 'Torch on',
    'qr_scanner_torch_off_tooltip': 'Torch off',
    'qr_scanner_switch_camera_tooltip': 'Switch camera',

    'qr_scanner_center_qr_instruction': 'Center the QR code within the frame',
    'qr_scanner_camera_permission_required': 'Camera permission is required',

    'qr_scanner_allow_camera_access_title': 'Allow Camera Access',
    'qr_scanner_allow_camera_access_description':
        'To scan league QR codes, enable camera permission.\n\nOr tap ENTER CODE to join manually.',
    'qr_scanner_open_settings': 'Open settings',
    'qr_scanner_grant_permission': 'Grant permission',

    'qr_scanner_scan_again': 'Scan again',

    'offline_banner_message': 'OFFLINE MODE: Scores will sync when back online',

    'admin_score_card_update_score': 'Update score',
    'glass_search_bar_hint': 'Search leagues...',
    'glass_group_card_empty_slot': '...',
    'generate_knockout_dialog_title': 'Generate Knockout Bracket',
    'generate_knockout_dialog_qualified_teams_intro': 'The following teams have qualified based on standings:',
    'generate_knockout_dialog_warning': 'This will create the knockout matchups. This action cannot be undone.',
    'generate_knockout_dialog_cancel': 'Cancel',
    'generate_knockout_dialog_start_knockouts': 'Start knockouts',

    'league_format_classic': 'Classic League',
    'league_format_ucl_group': 'Group League',
    'league_format_ucl_swiss': 'Series League',

    'league_flip_card_invite_code_copied': 'Invite code copied',
    'league_flip_card_tap_to_join_scan_qr': 'Tap to join / scan QR',
    'league_flip_card_double_tap_to_view_details': 'Double tap to view league details',
    'league_flip_card_invite_code_label': 'Invite code',
  },
};
