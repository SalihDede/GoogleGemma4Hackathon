import 'package:flutter_gemma/flutter_gemma.dart';

const _modelId = 'litert-community/gemma-4-E2B-it-litert-lm';
const _modelFile = 'gemma-4-E2B-it.litertlm';
const _commitHash = '7fa1d78473894f7e736a21d920c3aa80f950c0db';
const _modelUrl =
    'https://huggingface.co/$_modelId/resolve/$_commitHash/$_modelFile';

const _hfToken = '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';

class ModelManagerService {
  ModelManagerService._();
  static final ModelManagerService instance = ModelManagerService._();

  Future<bool> isModelInstalled() async {
    return FlutterGemma.isModelInstalled(_modelFile);
  }

  // Model zaten kuruluysa indirme olmaz — sadece active model spec set edilir.
  // Model kurulu değilse indirir (progress callback ile).
  Future<void> installOrActivate({
    void Function(int percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await FlutterGemma.initialize(huggingFaceToken: _hfToken);

    final builder = FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(_modelUrl, token: _hfToken);

    if (onProgress != null) builder.withProgress(onProgress);
    if (cancelToken != null) builder.withCancelToken(cancelToken);

    await builder.install();
  }
}
