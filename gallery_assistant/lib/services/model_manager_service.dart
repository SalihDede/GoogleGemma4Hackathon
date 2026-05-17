import 'package:flutter_gemma/flutter_gemma.dart';

import 'app_settings_service.dart';

const _modelId = 'litert-community/gemma-4-E2B-it-litert-lm';
const _modelFile = 'gemma-4-E2B-it.litertlm';
const _commitHash = '7fa1d78473894f7e736a21d920c3aa80f950c0db';
const _modelUrl =
    'https://huggingface.co/$_modelId/resolve/$_commitHash/$_modelFile';

class ModelManagerService {
  ModelManagerService._();
  static final ModelManagerService instance = ModelManagerService._();

  Future<bool> isModelInstalled() async {
    return FlutterGemma.isModelInstalled(_modelFile);
  }

  Future<void> activateInstalled() async {
    if (!await isModelInstalled()) {
      throw StateError('The offline model has not been downloaded yet.');
    }
    final token = await AppSettingsService.instance.huggingFaceTokenOrNull();
    await FlutterGemma.initialize(huggingFaceToken: token);

    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(_modelUrl, token: token).install();
  }

  Future<void> installOrActivate({
    void Function(int percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final token = await AppSettingsService.instance.huggingFaceTokenOrNull();
    await FlutterGemma.initialize(huggingFaceToken: token);

    final builder = FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(_modelUrl, token: token);

    if (onProgress != null) builder.withProgress(onProgress);
    if (cancelToken != null) builder.withCancelToken(cancelToken);

    await builder.install();
  }
}
