"""ローカルenvの自動読込とコンテナ環境変数の優先順位を検証する。"""
from app import config


def test_local_file_loads_independent_of_cwd(tmp_path, monkeypatch):
    path = tmp_path / '.local.env'
    path.write_text('GOOGLE_CLOUD_PROJECT=test-project\nRETRY_AFTER_SECONDS=17\n', encoding='utf-8-sig')
    monkeypatch.setattr(config, 'LOCAL_ENV_FILE', path)
    monkeypatch.delenv('GOOGLE_CLOUD_PROJECT', raising=False)
    monkeypatch.delenv('RETRY_AFTER_SECONDS', raising=False)
    monkeypatch.chdir(tmp_path.parent)
    settings = config.Settings.from_env()
    assert settings.project_id == 'test-project'
    assert settings.retry_after_seconds == 17
    assert 'GOOGLE_CLOUD_PROJECT' not in config.os.environ


def test_environment_overrides_file(tmp_path, monkeypatch):
    path = tmp_path / '.local.env'
    path.write_text('GOOGLE_CLOUD_PROJECT=file-project\n', encoding='utf-8')
    monkeypatch.setattr(config, 'LOCAL_ENV_FILE', path)
    monkeypatch.setenv('GOOGLE_CLOUD_PROJECT', 'container-project')
    assert config.Settings.from_env().project_id == 'container-project'


def test_missing_file_uses_environment(tmp_path, monkeypatch):
    monkeypatch.setattr(config, 'LOCAL_ENV_FILE', tmp_path / 'missing.env')
    monkeypatch.setenv('GOOGLE_CLOUD_PROJECT', 'cloud-project')
    assert config.Settings.from_env().project_id == 'cloud-project'

def test_project_is_not_inferred_from_flutter(tmp_path, monkeypatch):
    """API設定が未指定なら、フロントの設定から補完しない。"""
    monkeypatch.setattr(config, 'LOCAL_ENV_FILE', tmp_path / 'missing.env')
    monkeypatch.delenv('GOOGLE_CLOUD_PROJECT', raising=False)
    assert config.Settings.from_env().project_id is None