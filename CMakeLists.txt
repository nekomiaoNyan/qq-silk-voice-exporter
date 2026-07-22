cmake_minimum_required(VERSION 3.21)

cmake_policy(SET CMP0091 NEW)

project(qq_silk_exporter VERSION 1.3.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

option(QQ_SILK_BUILD_TESTS "Build and register tests" ON)

set(SILK_SDK_SOURCE_NAMES
    SKP_Silk_biquad.c
    SKP_Silk_bwexpander.c
    SKP_Silk_bwexpander_32.c
    SKP_Silk_CNG.c
    SKP_Silk_code_signs.c
    SKP_Silk_create_init_destroy.c
    SKP_Silk_dec_API.c
    SKP_Silk_decode_core.c
    SKP_Silk_decode_frame.c
    SKP_Silk_decode_parameters.c
    SKP_Silk_decode_pitch.c
    SKP_Silk_decode_pulses.c
    SKP_Silk_decoder_set_fs.c
    SKP_Silk_gain_quant.c
    SKP_Silk_lin2log.c
    SKP_Silk_log2lin.c
    SKP_Silk_LPC_inv_pred_gain.c
    SKP_Silk_LPC_synthesis_filter.c
    SKP_Silk_LPC_synthesis_order16.c
    SKP_Silk_LSF_cos_table.c
    SKP_Silk_MA.c
    SKP_Silk_NLSF_MSVQ_decode.c
    SKP_Silk_NLSF_stabilize.c
    SKP_Silk_NLSF2A.c
    SKP_Silk_NLSF2A_stable.c
    SKP_Silk_pitch_est_tables.c
    SKP_Silk_PLC.c
    SKP_Silk_range_coder.c
    SKP_Silk_resampler.c
    SKP_Silk_resampler_down2.c
    SKP_Silk_resampler_private_AR2.c
    SKP_Silk_resampler_private_ARMA4.c
    SKP_Silk_resampler_private_copy.c
    SKP_Silk_resampler_private_down_FIR.c
    SKP_Silk_resampler_private_down4.c
    SKP_Silk_resampler_private_IIR_FIR.c
    SKP_Silk_resampler_private_up2_HQ.c
    SKP_Silk_resampler_private_up4.c
    SKP_Silk_resampler_rom.c
    SKP_Silk_resampler_up2.c
    SKP_Silk_shell_coder.c
    SKP_Silk_sort.c
    SKP_Silk_sum_sqr_shift.c
    SKP_Silk_tables_gain.c
    SKP_Silk_tables_LTP.c
    SKP_Silk_tables_NLSF_CB0_10.c
    SKP_Silk_tables_NLSF_CB0_16.c
    SKP_Silk_tables_NLSF_CB1_10.c
    SKP_Silk_tables_NLSF_CB1_16.c
    SKP_Silk_tables_other.c
    SKP_Silk_tables_pitch_lag.c
    SKP_Silk_tables_pulses_per_block.c
    SKP_Silk_tables_sign.c
    SKP_Silk_tables_type_offset.c
)
list(TRANSFORM SILK_SDK_SOURCE_NAMES
    PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/third_party/silk-sdk/src/"
    OUTPUT_VARIABLE SILK_SDK_SOURCES
)

add_library(silk_sdk STATIC ${SILK_SDK_SOURCES})
target_include_directories(silk_sdk
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/silk-sdk/interface"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/silk-sdk/src"
)

add_executable(qq-silk src/qq_silk.c)
target_link_libraries(qq-silk PRIVATE silk_sdk)

if(WIN32)
    add_executable(wechat-voice src/wechat_voice.c)
    add_executable(wechat-record src/wechat_record.c)
    target_link_libraries(wechat-record PRIVATE ole32 mmdevapi)
endif()

if(MSVC)
    target_compile_definitions(silk_sdk PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(silk_sdk PRIVATE /O2 /GS /guard:cf)
    target_compile_options(qq-silk PRIVATE /W4 /O2 /GS /guard:cf /sdl /utf-8)
    target_compile_options(wechat-voice PRIVATE /W4 /O2 /GS /guard:cf /sdl /utf-8)
    target_compile_options(wechat-record PRIVATE /W4 /O2 /GS /guard:cf /sdl /utf-8)
    target_link_options(qq-silk PRIVATE
        /Brepro
        /CETCOMPAT
        /DYNAMICBASE
        /guard:cf
        /HIGHENTROPYVA
        /NXCOMPAT
    )
    target_link_options(wechat-voice PRIVATE
        /Brepro
        /CETCOMPAT
        /DYNAMICBASE
        /guard:cf
        /HIGHENTROPYVA
        /NXCOMPAT
    )
    target_link_options(wechat-record PRIVATE
        /Brepro
        /CETCOMPAT
        /DYNAMICBASE
        /guard:cf
        /HIGHENTROPYVA
        /NXCOMPAT
    )
elseif(MINGW)
    target_compile_options(silk_sdk PRIVATE -O2 -fstack-protector-strong)
    target_compile_options(qq-silk PRIVATE -Wall -Wextra -Wpedantic -O2 -fstack-protector-strong)
    target_compile_options(wechat-voice PRIVATE -Wall -Wextra -Wpedantic -O2 -fstack-protector-strong)
    target_compile_options(wechat-record PRIVATE -Wall -Wextra -Wpedantic -O2 -fstack-protector-strong)
    target_link_options(qq-silk PRIVATE -municode -Wl,--dynamicbase,--high-entropy-va,--nxcompat)
    target_link_options(wechat-voice PRIVATE -municode -Wl,--dynamicbase,--high-entropy-va,--nxcompat)
    target_link_options(wechat-record PRIVATE -municode -Wl,--dynamicbase,--high-entropy-va,--nxcompat)
else()
    target_compile_options(silk_sdk PRIVATE -O2 -fstack-protector-strong)
    target_compile_options(qq-silk PRIVATE -Wall -Wextra -Wpedantic -O2 -fstack-protector-strong)
endif()

if(QQ_SILK_BUILD_TESTS)
    include(CTest)
    if(BUILD_TESTING)
        if(WIN32)
            add_test(
                NAME cli_safety
                COMMAND powershell -NoLogo -NoProfile -ExecutionPolicy Bypass
                    -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-QQSilk.ps1"
                    -DecoderPath "$<TARGET_FILE:qq-silk>"
            )
            add_test(
                NAME wechat_voice_database
                COMMAND powershell -NoLogo -NoProfile -ExecutionPolicy Bypass
                    -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-WeChatVoice.ps1"
                    -ExtractorPath "$<TARGET_FILE:wechat-voice>"
            )
            add_test(
                NAME wechat_playback_recorder
                COMMAND powershell -NoLogo -NoProfile -ExecutionPolicy Bypass
                    -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-WeChatRecorder.ps1"
                    -RecorderPath "$<TARGET_FILE:wechat-record>"
            )
        endif()
    endif()
endif()

install(TARGETS qq-silk RUNTIME DESTINATION .)
if(WIN32)
    install(TARGETS wechat-voice wechat-record RUNTIME DESTINATION .)
endif()
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/Convert-QQVoice.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/Export-WeChatVoice.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/QQ-Silk-Converter-GUI.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/Start-VoiceConverter.cmd"
    "${CMAKE_CURRENT_SOURCE_DIR}/README.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
    DESTINATION .
)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/LICENSES" DESTINATION .)
